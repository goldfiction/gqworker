assert=require 'assert'
lib=require './../main.js'

it 'should be able to load',(done)->
  done()

it 'should be able to run as thread',(done)->
  func1="function method(o){return o.a+o.b}"
  o={a:3,b:5}
  lib.runAsThread func1,o,(e,r)->
    console.log e+":"+r
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
      console.log code+":"+text
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
#    console.log o
#    o.method=handler2
#    o
#  ).then(step).then (o)->
#    console.log o
#    done()

it 'should be able to run forkCluster',(done)->
  payload=(o)->
    app = require('express')()
    app.all '/*', (req, res)->
      res.send('process ' + process.pid + ' says hello!').end()
    server = app.listen 8000,()->
      console.log('Process ' + process.pid + ' is listening to all incoming requests')
  lib.forkCluster payload,{doNotForkNew:true,numWorkers:4,checkMaster:true},(e,o)->
    #setTimeout o.shutdown,1000
    assert o.workers.length==4
    setTimeout done,5000


