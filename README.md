======
cube_vmware_miner
======

* Indended to be deployed and have configuration rendered from template
* Can be run as a daemon or foreground, uses `daemons` gem documentation
* Runs periodically after configurable interval using `rufus-scheduler`
* Does not overlap runs, has configurable timeout
* Queries a Vsphere server for information about VMs and posts to Cube API
* Can post to Cube API on the fly or batch post at the end of a run
* Can log to syslog, local file or STDOUT

======
Author: John Coleman (<john-coleman@noreply.users.github.com>)
