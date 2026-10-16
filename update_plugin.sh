#!/usr/bin/env bash

cd agent || exit
pnpm remove '@empathic-engines/plugin-enhanced-memory'
pnpm add '../../dpankros_plugin-enhanced-memory'
cd ..
