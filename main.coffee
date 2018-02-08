workerThreads=require 'webworker-threads'
Worker = workerThreads.Worker
cluster = require 'cluster'
http = require 'http'
running = require 'is-running'

runAsThread=(method,o,cb)->
  workerThreads.create().eval(method).eval('method('+JSON.stringify(o)+')',cb)

exports.runAsThread=runAsThread

threadHandler=(handler,req,res)->
  o=req.body||req.query||{}
  # handler="function method(o){ return string to return }"
  runAsThread handler,o,(e,r)->
    if e
      res.send 404,JSON.stringify e
    else
      res.send 200,r

exports.threadHandler=threadHandler

closeWorker=()->
  console.log "Closing Worker"
  process._channel.close()
  process._channel.unref()
  require("fs").close(0)

forkCluster=(payload,o,cb)->
  numCPUs = o.numCPUs||require('os').cpus().length
  numWorkers = o.numWorkers||numCPUs
  cb=cb||()->

  if cluster.isMaster
    shutDownServer=(sig)->
      console.log "Closing All Worker Thread"
      shutDownAllWorker sig
      setTimeout ()->
        console.log "Closing Master"
        console.log 'Exiting.'
        process.exit 0
      ,100
    shutDownAllWorker=(sig)->
      console.log "Closing All Worker Thread"
      eachWorker (worker)->
        worker.send
          cmd: "stop"
    eachWorker=(callback)->
      for id in cluster.workers
        callback cluster.workers[id]
    i=0
    console.log('Master cluster setting up ' + numWorkers + ' workers...');
    workers=[]
    while(i < numWorkers)
      i++
      worker=cluster.fork()
      workers.push(worker)
    process.once 'SIGQUIT',()->
      console.log 'Received SIGQUIT'
      shutDownServer 'SIGQUIT'
    process.once 'SIGHUP',()->
      console.log 'Received SIGHUP'
      shutDownServer 'SIGHUP'
    process.once 'SIGINT',()->
      console.log 'Received SIGINT'
      process.exit()
    process.once 'SIGUSR2',()->
      console.log 'Received SIGUSR2'
      shutDownAllWorker 'SIGQUIT'
    cluster.on 'death',(worker)->
      console.log 'worker ' + worker.pid + ' died'
      if !o.doNotForkNew
        cluster.fork()
    cluster.on 'exit',(worker, code, signal)->
      exitCode = worker.process.exitCode
      console.log 'worker ' + worker.process.pid + ' died (' + exitCode + ').'
      if !o.doNotForkNew
        cluster.fork()

    if o.checkMaster
      # update worker master pid
      setInterval ()->
        eachWorker (worker)->
          worker.send
            masterpid: process.pid
      ,1000

    cluster.on 'online',(worker)->
      console.log 'Worker ' + worker.process.pid + ' is online'
    o.workers=workers
    o.cluster=cluster
    o.shutdown=()->
      shutDownServer(0)
    cb(null,o)
  else
    closeWorker=()->
      console.log "Closing Worker"
      process._channel.close()
      process._channel.unref()
      require("fs").close 0
    process.once 'SIGQUIT',()->
      closeWorker()
    process.once 'SIGINT',()->
      closeWorker()
    process.on 'exit',(code, signal)->
      if signal
        console.log "worker was killed by signal: " + signal
      else if code!=0
        console.log "worker exited with error code: " + code
      else
        console.log "worker success!"
    process.on 'message',(msg)->
        if msg=='stop'
          closeWorker()
    payload(o)

exports.forkCluster=forkCluster

global.gqworker=
  runAsThread:runAsThread
  threadHandler:threadHandler
  forkCluster:forkCluster
