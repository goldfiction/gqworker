workerThreads=require 'webworker-threads'
Worker = workerThreads.Worker
cluster = require 'cluster'
http = require 'http'
running = require 'is-running'
async=require 'async'
log=require('util').log

runAsThread=(method,o,cb)->
  thread=workerThreads.create()
  thread.eval(method).eval('method('+JSON.stringify(o)+')',(e,r)->
    cb(e,r)
    thread.destroy()
  )

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

forkCluster=(payload,o,cb)->
  o=o||{}
  numCPUs = o.numCPUs||require('os').cpus().length
  numWorkers = o.numWorkers||(numCPUs*2)
  o.cluster=cluster
  cb=cb||()->

  if cluster.isMaster
    updateMasterPID=()->
      eachWorker (worker)->
        try
          worker.send
            masterpid: process.pid
        catch e

    process.once 'SIGQUIT',()->
      log 'Received SIGQUIT'
      shutDownServer 'SIGQUIT'
    process.once 'SIGHUP',()->
      log 'Received SIGHUP'
      shutDownServer 'SIGHUP'
    process.once 'SIGINT',()->
      log 'Received SIGINT'
      process.exit()
    process.once 'SIGUSR2',()->
      log 'Received SIGUSR2'
      shutDownAllWorker 'SIGQUIT'
    cluster.on 'death',(worker)->
      exitCode = worker.process.exitCode
      log 'worker ' + worker.pid + ' died'
      if !o.doNotForkNew
        log 'worker '+"(" + worker.process.pid + ') exited with code ' + exitCode + '. Restarting...'
        cluster.fork()
        updateMasterPID()
    cluster.on 'exit',(worker, code, signal)->
      exitCode = worker.process.exitCode
      if(exitCode==7||o.doNotForkNew)
        log 'worker '+"(" + worker.process.pid + ') exited with code ' + exitCode + ' permanently.'
      else
        log 'worker '+"(" + worker.process.pid + ') exited with code ' + exitCode + '. Restarting...'
        cluster.fork()
        updateMasterPID()
    cluster.on 'online',(worker)->
      log 'Worker ' + worker.process.pid + ' is online'

    eachWorker=(callback)->
      for i,v of cluster.workers
        callback v

    shutDownAllWorker=(sig)->
      log "Closing All Worker Threads."
      eachWorker (worker)->
        worker.send
          cmd:"stop"

    shutDownServer=(sig)->
      sig=sig||0
      shutDownAllWorker sig
      setTimeout ()->
        log "Closing Master"
        log 'Exiting.'
        process.exit(0)
      ,100

    restartAllWorker=()->
      log "Restarting All Worker Threads."
      eachWorker (worker)->
        worker.send
          cmd:"restart"

    getWorkers=()->
      result=[]
      for i,v of cluster.workers
        result.push(v)
      return result

    cluster.shutDownServer=shutDownServer
    cluster.shutDownAllWorker=shutDownAllWorker
    cluster.eachWorker=eachWorker
    cluster.getWorkers=getWorkers

    log('Master cluster setting up ' + numWorkers + ' workers...');
    arr=[]
    for i in [1..numWorkers]
      arr.push(i)
    #log arr

    o.masterpid=process.id
    o.cluster=cluster
    async.mapLimit arr,4,(i,cb)->
      cluster.fork()
      cb()
    ,(e,r)->
      setTimeout ()->
        if o.checkMaster
          updateMasterPID()
        cb e,o
      ,3000
  else
    closeWorker=(sig)->
      sig=sig||0
      log "Closing Worker "+cluster.worker.id
      process._channel.close()
      process._channel.unref()
      process.exit(sig)

    #    process.once 'SIGQUIT',()->
    #      closeWorker()
    #    process.once 'SIGINT',()->
    #      closeWorker()
    #    process.on 'exit',(code, signal)->
    #      if signal
    #        log "worker ("+cluster.worker.id+") was killed by signal: " + signal
    #      else
    #        log "worker ("+cluster.worker.id+") exited with code: " + code

    process.on 'message',(msg)->
      if msg.cmd && (msg.cmd =='stop'||msg.cmd=="terminate")
        closeWorker(7)
      else if msg.cmd && msg.cmd =='restart'
        closeWorker(0)
    if (o.checkMaster)
      # check if master thread is alive every 30 seconds
      setInterval ()->
        try
          if (masterpid)
            running masterpid,(err,live)->
              if (err)
                log.info('failed to retrieve master running state')
              else
                if (live != true)
                  closeWorker(7)
        catch e
      ,60000
    payload(o)

exports.forkCluster=forkCluster

exports.gqworker=
  runAsThread:runAsThread
  threadHandler:threadHandler
  forkCluster:forkCluster
