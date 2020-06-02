import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { Zero, MaxUint256 } from 'ethers/constants'
import { BigNumber } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'
import IUniswapV2Pair from '@uniswap/v2-core/build/IUniswapV2Pair.json'

import { expandTo18Decimals } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

chai.use(solidity)

import DeflatingERC20 from '../build/DeflatingERC20.json'

const overrides = {
  gasLimit: 9999999
}

describe('UniswapV2RouterO3', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let DTT: Contract
  let WETH: Contract
  let router: Contract
  let pair: Contract

  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    WETH = fixture.WETH
    router = fixture.router03

    DTT = await deployContract(wallet, DeflatingERC20, [expandTo18Decimals(10000)])

    // make a DTT<>WETH pair
    await fixture.factoryV2.createPair(DTT.address, WETH.address)
    const pairAddress = await fixture.factoryV2.getPair(DTT.address, WETH.address)
    pair = new Contract(pairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet)
  })

  afterEach(async function() {
    expect(await provider.getBalance(router.address)).to.eq(Zero)
  })

  async function addLiquidity(DTTAmount: BigNumber, WETHAmount: BigNumber) {
    await DTT.approve(router.address, MaxUint256)
    await router.addLiquidityETH(DTT.address, DTTAmount, DTTAmount, WETHAmount, wallet.address, MaxUint256, {
      ...overrides,
      value: WETHAmount
    })
  }

  it('removeLiquidityETH', async () => {
    const DTTAmount = expandTo18Decimals(1)
    const ETHAmount = expandTo18Decimals(4)
    await addLiquidity(DTTAmount, ETHAmount)

    const DTTInPair = await DTT.balanceOf(pair.address)
    const WETHInPair = await WETH.balanceOf(pair.address)
    const liquidity = await pair.balanceOf(wallet.address)
    const totalSupply = await pair.totalSupply()
    const NaiveDTTExpected = DTTInPair.mul(liquidity).div(totalSupply)
    const WETHExpected = WETHInPair.mul(liquidity).div(totalSupply)

    await pair.approve(router.address, MaxUint256)
    await router.removeLiquidityETH(
      DTT.address,
      liquidity,
      NaiveDTTExpected,
      WETHExpected,
      wallet.address,
      MaxUint256,
      overrides
    )
  })

  it('swapExactTokensForTokens', async () => {
    const DTTAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(5)
    await addLiquidity(DTTAmount, ETHAmount)

    const amountIn = expandTo18Decimals(1)
    await DTT.approve(router.address, MaxUint256)
    await router.swapExactTokensForTokens(
      amountIn,
      Zero,
      [DTT.address, WETH.address],
      wallet.address,
      MaxUint256,
      overrides
    )
  })

  it('swapTokensForExactTokens', async () => {
    const DTTAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(5)
    await addLiquidity(DTTAmount, ETHAmount)

    const amountOut = expandTo18Decimals(1)
    await DTT.approve(router.address, MaxUint256)
    await router.swapTokensForExactTokens(
      amountOut,
      MaxUint256,
      [DTT.address, WETH.address],
      wallet.address,
      MaxUint256,
      overrides
    )
  })

  it('swapExactETHForTokens', async () => {
    const DTTAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(5)
    await addLiquidity(DTTAmount, ETHAmount)

    const amountIn = expandTo18Decimals(1)
    await router.swapExactETHForTokens(Zero, [WETH.address, DTT.address], wallet.address, MaxUint256, {
      ...overrides,
      value: amountIn
    })
  })

  it('swapTokensForExactETH', async () => {
    const DTTAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(5)
    await addLiquidity(DTTAmount, ETHAmount)

    const amountOut = expandTo18Decimals(1)
    await DTT.approve(router.address, MaxUint256)
    await router.swapTokensForExactETH(
      amountOut,
      MaxUint256,
      [DTT.address, WETH.address],
      wallet.address,
      MaxUint256,
      overrides
    )
  })

  it('swapExactTokensForETH', async () => {
    const DTTAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(5)
    await addLiquidity(DTTAmount, ETHAmount)

    const amountIn = expandTo18Decimals(1)
    await DTT.approve(router.address, MaxUint256)
    await router.swapExactTokensForETH(
      amountIn,
      Zero,
      [DTT.address, WETH.address],
      wallet.address,
      MaxUint256,
      overrides
    )
  })

  it('swapETHForExactTokens', async () => {
    const DTTAmount = expandTo18Decimals(5)
    const ETHAmount = expandTo18Decimals(5)
    await addLiquidity(DTTAmount, ETHAmount)

    const amountOut = expandTo18Decimals(1)
    await DTT.approve(router.address, MaxUint256)
    await router.swapETHForExactTokens(amountOut, [WETH.address, DTT.address], wallet.address, MaxUint256, {
      ...overrides,
      value: ETHAmount
    })
  })
})
