# TODO

- [ ] Replace `curl -fsSL https://deb.nodesource.com/setup_20.x | bash -` in Dockerfile with apt key method for Node.js installation — current curl-pipe-to-bash pattern is a known security risk (supply chain / MITM). See: https://github.com/nodesource/distributions
