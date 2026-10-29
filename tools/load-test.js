// Paso 9 de la parte 1 y pruebas de la parte 2: lanza N ejecuciones de newman en paralelo,
// equivalente a los comandos "newman run ... -n 10 &" del laboratorio.
// Uso: node load-test.js <part1|part2> <host> [paralelas=2] [iteraciones=10] [etiqueta]
//   node load-test.js part1 20.10.30.40 2 10 B1ls
//   node load-test.js part2 52.155.223.248 4 10 lb-4vms
var fs = require('fs');
var path = require('path');
var newman = require('newman');

var part = process.argv[2];
var host = process.argv[3];
var parallel = parseInt(process.argv[4] || '2', 10);
var iterations = parseInt(process.argv[5] || '10', 10);
var label = process.argv[6] || `${part}-${parallel}x${iterations}`;

if (!['part1', 'part2'].includes(part) || !host) {
  console.error('Uso: node load-test.js <part1|part2> <host> [paralelas=2] [iteraciones=10] [etiqueta]');
  process.exit(1);
}

var postmanDir = path.join(__dirname, '..', 'FibonacciApp', 'postman', part);
var collection = require(path.join(postmanDir, 'ARSW_LOAD-BALANCING_AZURE.postman_collection.json'));
var environment = require(path.join(postmanDir, '[ARSW_LOAD-BALANCING_AZURE].postman_environment.json'));
var hostVar = part === 'part1' ? 'VM1' : 'loadbalancer';
var outDir = path.join(__dirname, '..', 'reports', label);
fs.mkdirSync(outDir, { recursive: true });

function runOne(index) {
  return new Promise(function (resolve) {
    newman.run({
      collection: collection,
      environment: environment,
      envVar: [{ key: hostVar, value: host }],
      iterationCount: iterations,
      reporters: ['json'],
      reporter: { json: { export: path.join(outDir, `newman-${index}.json`) } }
    }, function (err, summary) {
      if (err) {
        console.error(`[run ${index}] error: ${err.message}`);
        return resolve(null);
      }
      var executions = summary.run.executions;
      var times = executions.filter(function (e) { return e.response; }).map(function (e) { return e.response.responseTime; });
      var failed = executions.filter(function (e) {
        return e.requestError || !e.response || e.response.code !== 200;
      });
      var errors = failed.map(function (e) {
        return e.requestError ? (e.requestError.code || e.requestError.message) : (e.response ? 'HTTP ' + e.response.code : 'sin respuesta');
      });
      resolve({
        index: index,
        total: executions.length,
        ok: executions.length - failed.length,
        failed: failed.length,
        min: times.length ? Math.min.apply(null, times) : 0,
        max: times.length ? Math.max.apply(null, times) : 0,
        avg: times.length ? Math.round(times.reduce(function (a, b) { return a + b; }, 0) / times.length) : 0,
        errors: Array.from(new Set(errors)).join(', ') || '-'
      });
    });
  });
}

(async function () {
  console.log(`Lanzando ${parallel} ejecuciones de newman en paralelo (${iterations} iteraciones c/u) contra ${host}...`);
  var start = Date.now();
  var runs = await Promise.all(Array.from({ length: parallel }, function (_, i) { return runOne(i + 1); }));
  runs = runs.filter(Boolean);
  var wall = ((Date.now() - start) / 1000).toFixed(1);

  var total = runs.reduce(function (s, r) { return s + r.total; }, 0);
  var ok = runs.reduce(function (s, r) { return s + r.ok; }, 0);

  var md = [
    `## Prueba de carga - ${label}`,
    '',
    `Host: \`${host}\` · ${parallel} ejecuciones paralelas × ${iterations} iteraciones · duración total ${wall} s`,
    '',
    '| Ejecución | Peticiones | Exitosas | Fallidas | Mín (ms) | Prom (ms) | Máx (ms) | Errores |',
    '|---|---|---|---|---|---|---|---|'
  ].concat(runs.map(function (r) {
    return `| ${r.index} | ${r.total} | ${r.ok} | ${r.failed} | ${r.min} | ${r.avg} | ${r.max} | ${r.errors} |`;
  })).concat([
    '',
    `**Tasa de éxito:** ${ok}/${total} (${total ? (ok * 100 / total).toFixed(1) : 0} %)`,
    ''
  ]).join('\n');

  fs.writeFileSync(path.join(outDir, 'summary.md'), md);
  console.log('\n' + md);
  console.log(`Reportes JSON y resumen en ${outDir}`);
})();
