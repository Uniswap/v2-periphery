import path from 'path'
import chai from 'chai'
import { solidity, createMockProvider, getWallets, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { Contract } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'
import { MaxUint256 } from 'ethers/constants'

import { expandTo18Decimals } from './shared/utilities'
import { exchangeFixture, ExchangeFixture } from './shared/fixtures'

import UniswapV2Router from '../build/UniswapV2Router.json'

chai.use(solidity)
const { expect } = chai

describe('UniswapV2Router', () => {
  const provider = createMockProvider(path.join(__dirname, '..', 'waffle.json'))
  const [wallet] = getWallets(provider)
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token0: Contract
  let token1: Contract
  let exchange: Contract
  let wETH: Contract
  let wETHPair: Contract
  let wETHExchange: Contract
  let router: Contract
  beforeEach(async function() {
    const {
      factory,
      token0: _token0,
      token1: _token1,
      exchange: _exchange,
      wETH: _wETH,
      wETHPair: _wETHPair,
      wETHExchange: _wETHExchange
    }: ExchangeFixture = await loadFixture(exchangeFixture as any)
    token0 = _token0
    token1 = _token1
    exchange = _exchange
    wETH = _wETH
    wETHPair = _wETHPair
    wETHExchange = _wETHExchange

    router = await deployContract(wallet, UniswapV2Router, [factory.address, wETH.address])
  })

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(exchange.address, token0Amount)
    await token1.transfer(exchange.address, token1Amount)
    await exchange.connect(wallet).mintLiquidity(wallet.address)
  }

  it('swapExactTokensForTokens', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    await token0.approve(router.address, MaxUint256)
    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')
    await expect(
      router.swapExactTokensForTokens(
        token0.address,
        swapAmount,
        token1.address,
        wallet.address,
        expectedOutputAmount,
        MaxUint256
      )
    )
      .to.emit(exchange, 'Swap')
      .withArgs(router.address, wallet.address, token0.address, swapAmount, expectedOutputAmount)
  })

  it('swapExactTokensForTokens:fail', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    await token0.approve(router.address, MaxUint256)
    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')

    await expect(
      router.swapExactTokensForTokens(
        token0.address,
        swapAmount,
        token1.address,
        wallet.address,
        expectedOutputAmount,
        Math.floor(Date.now() / 1000) - 1
      )
    ).to.be.revertedWith('UniswapV2Router: EXPIRED')

    await expect(
      router.swapExactTokensForTokens(
        token0.address,
        swapAmount,
        token1.address,
        wallet.address,
        expectedOutputAmount.add(1),
        MaxUint256
      )
    ).to.be.revertedWith('UniswapV2Router: MINIMUM_NOT_EXCEEDED')
  })

  async function addwETHLiquidity(wETHAmount: BigNumber, wETHPairAmount: BigNumber) {
    await wETH.deposit({ value: wETHAmount })
    await wETH.transfer(wETHExchange.address, wETHAmount)
    await wETHPair.transfer(wETHExchange.address, wETHPairAmount)
    await wETHExchange.connect(wallet).mintLiquidity(wallet.address)
  }

  it('swapExactETHForTokens', async () => {
    const wETHAmount = expandTo18Decimals(5)
    const wETHPairAmount = expandTo18Decimals(10)
    await addwETHLiquidity(wETHAmount, wETHPairAmount)

    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')
    await expect(
      router.swapExactETHForTokens(wETHPair.address, wallet.address, expectedOutputAmount, MaxUint256, {
        value: swapAmount
      })
    )
      .to.emit(exchange, 'Swap')
      .withArgs(router.address, wallet.address, wETH.address, expectedOutputAmount, swapAmount) // wETH is token1
  })
})
