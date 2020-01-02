import path from 'path'
import chai from 'chai'
import { solidity, createMockProvider, getWallets, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { Contract } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'

import { expandTo18Decimals } from './shared/utilities'
import { exchangeFixture, ExchangeFixture } from './shared/fixtures'

import UniswapV2OracleExample from '../build/UniswapV2OracleExample.json'

chai.use(solidity)
const { expect } = chai

const overrides = {
  gasLimit: 1000000
}

describe('UniswapV2OracleExample', () => {
  const provider = createMockProvider(path.join(__dirname, '..', 'waffle.json'))
  const [wallet] = getWallets(provider)
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token0: Contract
  let token1: Contract
  let exchange: Contract
  let oracle: Contract
  beforeEach(async function() {
    const { factory, token0: _token0, token1: _token1, exchange: _exchange }: ExchangeFixture = await loadFixture(
      exchangeFixture as any
    )

    token0 = _token0
    token1 = _token1
    exchange = _exchange
    oracle = await deployContract(wallet, UniswapV2OracleExample, [factory.address, token0.address, token1.address])
  })

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(exchange.address, token0Amount)
    await token1.transfer(exchange.address, token1Amount)
    await exchange.connect(wallet).mint(wallet.address, overrides)
  }

  it('initialize', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)
    await oracle.initialize()
  })

  it('update', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)
    await oracle.initialize()
    await oracle.update()

    expect((await oracle.price0Average()).toString()).to.eq(
      bigNumberify(2)
        .pow(113)
        .toString()
    )
    expect((await oracle.price1Average()).toString()).to.eq(
      bigNumberify(2)
        .pow(111)
        .toString()
    )
  })

  it('quote0, quote1', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)
    await oracle.initialize()
    await oracle.update()

    expect((await oracle.quote(token0.address, token0Amount)).toString()).to.eq(token1Amount)
    expect((await oracle.quote(token1.address, token1Amount)).toString()).to.eq(token0Amount)
  })
})
