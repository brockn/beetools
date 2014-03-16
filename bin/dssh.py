#!/usr/bin/python -W ignore
import sys, os, threading, subprocess
from time import sleep
from Queue import Queue
program = "dssh"
class PipeReader(threading.Thread):
  def __init__(self, pipe):
    threading.Thread.__init__(self)
    self.pipe = pipe
    self.lines = []
  def run (self):
    for line in self.pipe:
      self.lines.append(line[0:-1])

class RemoteCommand(threading.Thread):
  def __init__(self, host, cmd, options=[]):
    threading.Thread.__init__(self)
    self.host = host
    self.cmd = cmd
    self.options = options
    self.output = []
    self.error = []
    self.returncode = -1
  def run(self):
    args = [ "ssh" ] + self.options + [ self.host ] +  self.cmd
    p = subprocess.Popen(args, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, close_fds=True)
    # Should be able to replace PipeReader with p.communicate()
    stdoutReader = PipeReader(p.stdout)
    stdoutReader.start()

    stderrReader = PipeReader(p.stderr)
    stderrReader.start()

    stdoutReader.join()
    stderrReader.join()

    p.wait()

    self.output = stdoutReader.lines
    self.error = stderrReader.lines # this version of open appears to that error = output
    self.returncode = p.returncode

def waitWhileAlive(threads, until=None):
  if until:
    alive = until + 1
    while alive >= until:
      alive = 0
      for thread in threads:
        if thread.isAlive():
          alive += 1
      if alive > until:
        sleep(0.01)
    return alive
  for thread in threads:
    thread.join()
  return 0

if __name__ == '__main__':
  args = sys.argv[1:]
  sshopts = []
  remoteCmd = []
  if "--" in args:
    i = args.index("--")
    sshopts = args[:i]
    remoteCmd = args[i+1:]
  else:
    remoteCmd = args
  cmdList = []
  aliveList = []
  hostList = []
  for line in sys.stdin:
    hostList.append(line.strip())
  MAX_WIDTH = 10
  while len(hostList) > 0:
    alive = 0
    if aliveList:
      alive = waitWhileAlive(aliveList, MAX_WIDTH)
    for i in xrange(0, (MAX_WIDTH - alive)):
      try:
        host = hostList.pop()
        cmd = RemoteCommand(host, remoteCmd, sshopts)
        cmd.start()
        cmdList.append(cmd)
        aliveList.append(cmd)
      except IndexError:
        break
  waitWhileAlive(aliveList)
  for cmd in cmdList:
    if cmd.returncode == 0:
      prefix = ""
      suffix = ""
    else:
      prefix = "\x1b[0;31;40m"
      suffix = "\x1b[0m"
    for line in cmd.error:
      print "\x1b[0;31;40m%s:%d:E: %s\x1b[0m" % (cmd.host, cmd.returncode, line)
    for line in cmd.output:
      print "%s%s:%d: %s%s" % (prefix, cmd.host, cmd.returncode, line, suffix)
