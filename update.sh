#!/bin/bash
git fetch && git pull && cargo build --release && sudo systemctl restart resourcer && sudo journalctl -u resourcer -n 100 --no-pager
