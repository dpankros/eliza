#!/usr/bin/env bash

cd agent || exit
pnpm remove '@dpankros/plugin-enhanced-memory'
pnpm add '../../dpankros_plugin-enhanced-memory'
cd ..
