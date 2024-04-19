# OffBlocks Modules

This project experiments with ERC-7579 modular smart accounts and various payments use-cases from OffBlocks. The main modules at the moment are:

- `DelayedExecution`: A module delaying the execution of a transaction and converting it into a two-step process. This is useful for cases where we don't want to execute a transaction immediately, but rather after a certain period of time guaranteeing that we can prioritise whitelisted transactions in the meantime.
- `FiatPayment`: A module that facilitates crypto-to-fiat payments, such as card payments, by converting the payment into a two-step process. The first step is to reserve the funds in the user's account, and the second step is to execute the payment after the payment network has confirmed the status of the payment and is ready to settle. This module also introduces auxillary `SpendLimit` contract managing the user's spend limits for specified tokens on a daily and monthly basis.

## Deployments

Base Sepolia:

- `DelayedExecution`: [0xe8378E081ed4bef31E98F2341D84B5D48508bf88](https://sepolia.basescan.org/address/0xe8378E081ed4bef31E98F2341D84B5D48508bf88)
- `FiatPayment`: [0x297dC4DFa25DD216ae1A317881B87C72208Abb81](https://sepolia.basescan.org/address/0x297dC4DFa25DD216ae1A317881B87C72208Abb81)

## Development

Compiling the contracts:

```shell
npx hardhat compile
```

Running the tests:

```shell
npx hardhat test
REPORT_GAS=true npx hardhat test
```

Deploying the contracts:

```shell
npx hardhat ignition deploy ignition/modules/DelayedExecution.ts --network baseSepolia --strategy create2 --parameters ignition/baseSepolia.json --verify
npx hardhat ignition deploy ignition/modules/FiatPayment.ts --network baseSepolia --strategy create2 --parameters ignition/baseSepolia.json --verify
```

Running the playground:

```shell
npx hardhat run scripts/playground.ts
```
