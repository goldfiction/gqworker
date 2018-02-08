var Worker, closeWorker, cluster, forkCluster, http, runAsThread, running, threadHandler, workerThreads;

workerThreads = require('webworker-threads');

Worker = workerThreads.Worker;

cluster = require('cluster');

http = require('http');

running = require('is-running');

runAsThread = function(method, o, cb) {
    return workerThreads.create()["eval"](method)["eval"]('method(' + JSON.stringify(o) + ')', cb);
};

exports.runAsThread = runAsThread;

threadHandler = function(handler, req, res) {
    var o;
    o = req.body || req.query || {};
    return runAsThread(handler, o, function(e, r) {
        if (e) {
            return res.send(404, JSON.stringify(e));
        } else {
            return res.send(200, r);
        }
    });
};

exports.threadHandler = threadHandler;

closeWorker = function() {
    console.log("Closing Worker");
    process._channel.close();
    process._channel.unref();
    return require("fs").close(0);
};

forkCluster = function(payload, o, cb) {
    var eachWorker, i, numCPUs, numWorkers, shutDownAllWorker, shutDownServer, worker, workers;
    numCPUs = o.numCPUs || require('os').cpus().length;
    numWorkers = o.numWorkers || numCPUs;
    cb = cb || function() {};
    if (cluster.isMaster) {
        shutDownServer = function(sig) {
            console.log("Closing All Worker Thread");
            shutDownAllWorker(sig);
            return setTimeout(function() {
                console.log("Closing Master");
                console.log('Exiting.');
                return process.exit(0);
            }, 100);
        };
        shutDownAllWorker = function(sig) {
            console.log("Closing All Worker Thread");
            return eachWorker(function(worker) {
                return worker.send({
                    cmd: "stop"
                });
            });
        };
        eachWorker = function(callback) {
            var id, j, len, ref, results;
            ref = cluster.workers;
            results = [];
            for (j = 0, len = ref.length; j < len; j++) {
                id = ref[j];
                results.push(callback(cluster.workers[id]));
            }
            return results;
        };
        i = 0;
        console.log('Master cluster setting up ' + numWorkers + ' workers...');
        workers = [];
        while (i < numWorkers) {
            i++;
            worker = cluster.fork();
            workers.push(worker);
        }
        process.once('SIGQUIT', function() {
            console.log('Received SIGQUIT');
            return shutDownServer('SIGQUIT');
        });
        process.once('SIGHUP', function() {
            console.log('Received SIGHUP');
            return shutDownServer('SIGHUP');
        });
        process.once('SIGINT', function() {
            console.log('Received SIGINT');
            return process.exit();
        });
        process.once('SIGUSR2', function() {
            console.log('Received SIGUSR2');
            return shutDownAllWorker('SIGQUIT');
        });
        cluster.on('death', function(worker) {
            console.log('worker ' + worker.pid + ' died');
            if (!o.doNotForkNew) {
                return cluster.fork();
            }
        });
        cluster.on('exit', function(worker, code, signal) {
            var exitCode;
            exitCode = worker.process.exitCode;
            console.log('worker ' + worker.process.pid + ' died (' + exitCode + ').');
            if (!o.doNotForkNew) {
                return cluster.fork();
            }
        });
        if (o.checkMaster) {
            setInterval(function() {
                return eachWorker(function(worker) {
                    return worker.send({
                        masterpid: process.pid
                    });
                });
            }, 1000);
        }
        cluster.on('online', function(worker) {
            return console.log('Worker ' + worker.process.pid + ' is online');
        });
        o.workers = workers;
        o.cluster = cluster;
        o.shutdown = function() {
            return shutDownServer(0);
        };
        return cb(null, o);
    } else {
        closeWorker = function() {
            console.log("Closing Worker");
            process._channel.close();
            process._channel.unref();
            return require("fs").close(0);
        };
        process.once('SIGQUIT', function() {
            return closeWorker();
        });
        process.once('SIGINT', function() {
            return closeWorker();
        });
        process.on('exit', function(code, signal) {
            if (signal) {
                return console.log("worker was killed by signal: " + signal);
            } else if (code !== 0) {
                return console.log("worker exited with error code: " + code);
            } else {
                return console.log("worker success!");
            }
        });
        process.on('message', function(msg) {
            if (msg === 'stop') {
                return closeWorker();
            }
        });
        return payload(o);
    }
};

exports.forkCluster = forkCluster;

global.gqworker = {
    runAsThread: runAsThread,
    threadHandler: threadHandler,
    forkCluster: forkCluster
};

// ---
// generated by coffee-script 1.9.2