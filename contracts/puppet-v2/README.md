# How to run
1. Go to the project root directory.

2. Run:
    ```
    etheno --ganache --ganache-args "--deterministic --gasLimit 10000000" -x contracts/puppet-v2/init.json
    ```
    *It will start a `ganache` instance and, when killed, will save the current blockchain state (deployed contracts, transactions made) to `init.json` file, which will be used later.*

3. In a separate terminal, run:
    ```
    npx hardhat run contracts/puppet-v2/scripts/deploy.js --network localhost
    ```
    *It will do a necessary setup, similar to the original one from DamnVulnerableDeFi challenge. It will also print addresses of deployed contracts, that should be filled in [PuppetV2PoolEchidna.sol](./PuppetV2PoolEchidna.sol).*

4. Fill the addresses of the following variables in [PuppetV2PoolEchidna.sol](./PuppetV2PoolEchidna.sol):
- token 
- lendingPool 
- weth
- uniswapRouter

    using the values acquired in the step 3.

5. Go back to the terminal where `etheno` is run and press `CTRL+C` in order to kill it.

6. Run:
    ```
    echidna-test . --contract PuppetV2PoolEchidna --config puppet-v2.yaml
    ```
    in order to start fuzzing.