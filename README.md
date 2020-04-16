# Uniswap V2

[![Actions Status](https://github.com/Uniswap/uniswap-v2-periphery/workflows/CI/badge.svg)](https://github.com/Uniswap/uniswap-v2-periphery/actions)

In-depth documentation on Uniswap V2 is available at [uniswap.org](https://uniswap.org/docs).

# Local Development

The following assumes the use of `node@>=10`.

## Clone Repository

`git clone https://github.com/Uniswap/uniswap-v2-periphery.git`

## Install Dependencies

`yarn`

## Compile Contracts

`yarn compile`

## Prepare for deployment
The build artifacts include constants that refer to addresses of test contracts. We must replace these constants with
production values before deployment. They are constants rather than variables for compile time gains on gas efficiency.

We cannot use [ethereum/solidity#3835](https://github.com/ethereum/solidity/issues/3835) in the current version of solc. 

So a script has been written that replaces the constants in the bytecode with the desired value.

## Run Tests

`yarn test`
