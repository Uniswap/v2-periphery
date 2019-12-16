import path from 'path'
import chai from 'chai'
import { solidity, createMockProvider, getWallets, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { Contract } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'
import { AddressZero } from 'ethers/constants'

import { expandTo18Decimals } from './shared/utilities'
import { exchangeFixture, ExchangeFixture } from './shared/fixtures'

import WETH9 from '../build/WETH9.json'
import UniswapV2Router from '../build/UniswapV2Router.json'

chai.use(solidity)
const { expect } = chai

describe('UniswapV2Router', () => {
  const provider = createMockProvider(path.join(__dirname, '..', 'waffle.json'))
  const [wallet] = getWallets(provider)
  const loadFixture = createFixtureLoader(provider, [wallet])

  let wETH: Contract
  let token0: Contract
  let token1: Contract
  let exchange: Contract
  let router: Contract
  beforeEach(async function() {
    wETH = await deployContract(wallet, WETH9)

    const { factory, token0: _token0, token1: _token1, exchange: _exchange }: ExchangeFixture = await loadFixture(
      exchangeFixture as any
    )

    token0 = _token0
    token1 = _token1
    exchange = _exchange
    router = await deployContract(wallet, UniswapV2Router, [factory.address, AddressZero])
  })

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(exchange.address, token0Amount)
    await token1.transfer(exchange.address, token1Amount)
    await exchange.connect(wallet).mintLiquidity(wallet.address)
  }

  it('initialize', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)
    // console.log(wETH)
    // console.log(router)
  })
})
