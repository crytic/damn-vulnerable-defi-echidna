# Damn-vulnerable-defi - Echidna edition

This repo is meant to be used with exercises 5 and 6 of [Building-secure-contracts/Echidna](https://github.com/crytic/building-secure-contracts/tree/master/program-analysis/echidna).

Only two challenges are currently supported (naive receiver, and unstoppable).
The changes made to the origina repo:
- Remove the `dependencyCompiler` section in `hardhat.config.js`
- Enable transfers of tokens in `contracts/the-rewarder/AccountingToken.sol` (the original mock token does not allow transfers, limiting the fuzzer exploration)

Below is the original readme

![](cover.png)

**A set of challenges to hack implementations of DeFi in Ethereum.**

Featuring flash loans, price oracles, governance, NFTs, lending pools, smart contract wallets, timelocks, and more!

Created by [@tinchoabbate](https://twitter.com/tinchoabbate)

## Usage

You will need  [Echidna](https://github.com/crytic/echidna) installed before proceeding.

Install the dependencies via `yarn install`.

```sh
git clone https://github.com/crytic/damn-vulnerable-defi-echidna
cd damn-vulnerable-defi-echidna
yarn install
echidna-test <contract_path> --contract <contract_name> --config echidna-config.yaml
```

## Play

Visit [damnvulnerabledefi.xyz](https://damnvulnerabledefi.xyz)

## Disclaimer

All Solidity code, practices and patterns in this repository are DAMN VULNERABLE and for educational purposes only.

DO NOT USE IN PRODUCTION.
