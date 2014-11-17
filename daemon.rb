#!/usr/bin/env ruby
require 'rubygems'
require_relative 'lib/cube/daemon.rb'
require_relative 'lib/cube/daemon/vmware_miner.rb'

config_path = File.join(File.dirname(File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__), 'config')
config_name = File.join(config_path, 'daemon.yml')
config = Cube::Daemon.load_config(File.expand_path(config_name))
Cube::Daemon.run(Cube::Daemon::VmwareMiner.new(config, Cube::Daemon.api_client, Cube::Daemon.logger))
