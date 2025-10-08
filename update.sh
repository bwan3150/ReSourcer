#!/bin/bash

sudo -v

git fetch && git pull && cargo build --release && sudo systemctl restart resourcer && sudo journalctl -u resourcer -n 35 --no-pager
