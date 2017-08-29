#!/bin/bash

BASEDIR=$(dirname "$0")
cd $BASEDIR
ruby ${BASEDIR}/update_pb_project.rb
