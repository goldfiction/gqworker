assert=require 'assert'
lib=require './../main.js'
log=require('util').log

cluster={}

it 'should be able to load',(done)->
  done()

it 'should be able to run as thread',(done)->
  func1="function method(o){return o.a+o.b}"
  o={a:3,b:5}
  lib.runAsThread func1,o,(e,r)->
    #log e+":"+r
    assert e+":"+r=="null:8"
    done()

it 'should be able to run thread handler',(done)->
  handler="function method(o){return o.a+o.b}"
  req=
    body:
      a:3
      b:5
  res=
    send:(code,text)->
      #log code+":"+text
      assert code+":"+text=="200:8"
      done()
  lib.threadHandler handler,req,res

#it 'should be able to run q handler',(done)->
#  o={a:2,b:3,c:4}
#  handler1="function method(o){return o.a+o.b}"
#  handler2="function method(o){return o.a+o.c}"
#  step=lib.qAsThread
#  o.method=handler1
#  step(o)
#  .then((o)->
#    log o
#    o.method=handler2
#    o
#  ).then(step).then (o)->
#    log o
#    done()

#after (done)->
#  cluster.shutDownServer(7)
#  setTimeout done,5000


it 'should be able to run forkCluster',(done)->
  payload=(o)->
    app = require('express')()
    app.all '/*', (req, res)->
      res.send('process ' + process.pid + ' says hello!').end()
    server = app.listen 8010,()->
      log('Process ' + process.pid + ' is listening to all incoming requests')
  lib.forkCluster payload,{doNotForkNew:false,numWorkers:4,checkMaster:true},(e,o)->
    if e
      console.error e
    #setTimeout o.shutdown,1000
    cluster=o.cluster
    if cluster.isMaster
      setTimeout ()->
        assert cluster.getWorkers().length==4
        setTimeout ()->
          cluster.getWorkers()[0].send({cmd:"terminate"})
          cluster.getWorkers()[1].send({cmd:"restart"})
          setTimeout ()->
            assert cluster.getWorkers().length==3
            setTimeout ()->
                done()
            ,1000
          ,2000
        ,1000
      ,1000
    
after (done)->
  setTimeout ()->
    done()
  ,2000
  cluster.shutDownServer(7)
