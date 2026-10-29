// Paso 7 de la parte 1: mide el tiempo de respuesta de /fibonacci/:nth para los valores del laboratorio.
// Uso: node measure-times.js <host[:puerto]> [etiqueta]
//   node measure-times.js 20.10.30.40:3000 B1ls
//   node measure-times.js 52.155.223.248 load-balancer
// Las peticiones se hacen una a una (secuenciales) para medir solo el tiempo de calculo.
var fs = require('fs');
var path = require('path');

var VALUES = [1000000, 1010000, 1020000, 1030000, 1040000, 1050000, 1060000, 1070000, 1080000, 1090000];

var host = process.argv[2];
var label = process.argv[3] || 'run';
if (!host) {
  console.error('Uso: node measure-times.js <host[:puerto]> [etiqueta]');
  process.exit(1);
}

async function measure(nth) {
  var start = Date.now();
  try {
    var res = await fetch(`http://${host}/fibonacci/${nth}`);
    await res.text();
    return { nth: nth, ms: Date.now() - start, status: res.status, servedBy: res.headers.get('x-served-by') || '-' };
  } catch (err) {
    return { nth: nth, ms: Date.now() - start, status: 'ERROR: ' + (err.cause ? err.cause.code : err.message), servedBy: '-' };
  }
}

(async function () {
  var rows = [];
  for (var nth of VALUES) {
    var r = await measure(nth);
    console.log(`${r.nth}\t${r.ms} ms\t${r.status}\t${r.servedBy}`);
    rows.push(r);
  }

  var ok = rows.filter(function (r) { return r.status === 200; });
  var avg = ok.length ? Math.round(ok.reduce(function (s, r) { return s + r.ms; }, 0) / ok.length) : 0;

  var md = [
    `## Tiempos de respuesta - ${label} (${host})`,
    '',
    '| nth | Tiempo (ms) | Tiempo (s) | Estado | Nodo |',
    '|---|---|---|---|---|'
  ].concat(rows.map(function (r) {
    return `| ${r.nth} | ${r.ms} | ${(r.ms / 1000).toFixed(2)} | ${r.status} | ${r.servedBy} |`;
  })).concat(['', `Promedio (exitosas): ${avg} ms`, '']).join('\n');

  var outDir = path.join(__dirname, '..', 'reports');
  fs.mkdirSync(outDir, { recursive: true });
  var outFile = path.join(outDir, `times-${label}.md`);
  fs.writeFileSync(outFile, md);
  console.log(`\nPromedio: ${avg} ms. Tabla guardada en ${outFile}`);
})();
