var express = require('express');
var os = require('os');
var FibonacciService = require('./Services/FibonacciService')

var app = express();
var port = process.env.PORT || 3000;

// Identifica que nodo respondio (util para verificar el balanceo en la parte 2)
app.use(function (req, res, next) {
  res.set('X-Served-By', os.hostname());
  next();
});

app.get('/fibonacci/:nthIn', function (req, res) {
  var nthIn = req.params.nthIn;
  if (!/^\d+$/.test(nthIn)) {
    return res.status(400).send('nth must be a non-negative integer');
  }

  var start = Date.now();
  var nth = FibonacciService.getNthNumberInSequence(parseInt(nthIn, 10))
  console.log(`Calculated ${nthIn} in ${Date.now() - start} ms`);
  res.send('The answer is ' + nth);
});

app.get('/', function (req, res) {
  res.send('Hello World');
});

app.listen(port, function () {
  console.log(`Fibonacci App listening on port ${port}!`);
});
