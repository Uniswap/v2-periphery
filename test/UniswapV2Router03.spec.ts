import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { Zero, MaxUint256 } from 'ethers/constants'
import { BigNumber, bigNumberify } from 'ethers/utils'
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
  let routerEventEmitter: Contract
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    WETH = fixture.WETH
    router = fixture.router03

    DTT = await deployContract(wallet, DeflatingERC20, [expandTo18Decimals(10000)])

    // make a DTT<>WETH pair
    await fixture.factoryV2.createPair(DTT.address, WETH.address)
    const pairAddress = await fixture.factoryV2.getPair(DTT.address, WETH.address)
    pair = new Contract(pairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet)

    routerEventEmitter = fixture.routerEventEmitter
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

  // DTT -> WETH
  describe('swapExactTokensForTokens', () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(10)
    const amountIn = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')

    it('happy path', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
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

    it('amounts', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(routerEventEmitter.address, MaxUint256)

      await expect(
        routerEventEmitter.swapExactTokensForTokens(
          router.address,
          amountIn,
          Zero,
          [DTT.address, WETH.address],
          wallet.address,
          MaxUint256,
          overrides
        )
      )
        .to.emit(routerEventEmitter, 'Amounts')
        // we get less than expected because of the fee
        .withArgs([amountIn, expectedOutputAmount.sub(bigNumberify('13884162227552551'))])
    })
  })

  // DTT -> WETH
  describe('swapTokensForExactTokens', () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(10)
    const expectedSwapAmount = bigNumberify('557227237267357629')
    const outputAmount = expandTo18Decimals(1)

    it('happy path', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(router.address, MaxUint256)

      await router.swapTokensForExactTokens(
        outputAmount,
        MaxUint256,
        [DTT.address, WETH.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    })

    it('amounts', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(routerEventEmitter.address, MaxUint256)

      await expect(
        routerEventEmitter.swapTokensForExactTokens(
          router.address,
          outputAmount,
          MaxUint256,
          [DTT.address, WETH.address],
          wallet.address,
          MaxUint256,
          overrides
        )
      )
        .to.emit(routerEventEmitter, 'Amounts')
        // we get less than expected because of the fee
        .withArgs([expectedSwapAmount, outputAmount.sub(bigNumberify('9009009009009008'))])
    })
  })

  // ETH -> DTT
  describe('swapExactETHForTokens', () => {
    const DTTAmount = expandTo18Decimals(10)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(5)
    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')

    it('happy path', async () => {
      await addLiquidity(DTTAmount, ETHAmount)

      await router.swapExactETHForTokens(Zero, [WETH.address, DTT.address], wallet.address, MaxUint256, {
        ...overrides,
        value: swapAmount
      })
    })

    it('amounts', async () => {
      await addLiquidity(DTTAmount, ETHAmount)

      await expect(
        routerEventEmitter.swapExactETHForTokens(
          router.address,
          Zero,
          [WETH.address, DTT.address],
          wallet.address,
          MaxUint256,
          {
            ...overrides,
            value: swapAmount
          }
        )
      )
        .to.emit(routerEventEmitter, 'Amounts')
        // we're actually going to get less than expectedOutputAmount because a fee will be taken
        .withArgs([swapAmount, expectedOutputAmount])
    })
  })

  // DTT -> ETH
  describe('swapTokensForExactETH', () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(10)
    const expectedSwapAmount = bigNumberify('557227237267357629')
    const outputAmount = expandTo18Decimals(1)

    it('happy path', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(router.address, MaxUint256)

      await router.swapTokensForExactETH(
        outputAmount,
        MaxUint256,
        [DTT.address, WETH.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    })

    it('amounts', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(routerEventEmitter.address, MaxUint256)

      await expect(
        routerEventEmitter.swapTokensForExactETH(
          router.address,
          outputAmount,
          MaxUint256,
          [DTT.address, WETH.address],
          wallet.address,
          MaxUint256,
          overrides
        )
      )
        .to.emit(routerEventEmitter, 'Amounts')
        // we get less than expected because of the fee
        .withArgs([expectedSwapAmount, outputAmount.sub(bigNumberify('9009009009009008'))])
    })
  })

  // DTT -> ETH
  describe('swapExactTokensForETH', () => {
    const DTTAmount = expandTo18Decimals(5)
      .mul(100)
      .div(99)
    const ETHAmount = expandTo18Decimals(10)
    const swapAmount = expandTo18Decimals(1)
    const expectedOutputAmount = bigNumberify('1662497915624478906')

    it('happy path', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(router.address, MaxUint256)

      await router.swapExactTokensForETH(
        swapAmount,
        Zero,
        [DTT.address, WETH.address],
        wallet.address,
        MaxUint256,
        overrides
      )
    })

    it('amounts', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(routerEventEmitter.address, MaxUint256)

      await expect(
        routerEventEmitter.swapExactTokensForETH(
          router.address,
          swapAmount,
          Zero,
          [DTT.address, WETH.address],
          wallet.address,
          MaxUint256,
          overrides
        )
      )
        .to.emit(routerEventEmitter, 'Amounts')
        .withArgs([swapAmount, expectedOutputAmount.sub(bigNumberify('13884162227552551'))])
    })
  })

  // ETH -> DTT
  describe('swapETHForExactTokens', () => {
    const DTTAmount = expandTo18Decimals(10)
    const ETHAmount = expandTo18Decimals(5)
    const expectedSwapAmount = bigNumberify('557227237267357629')
    const outputAmount = expandTo18Decimals(1)

    it('happy path', async () => {
      await addLiquidity(DTTAmount, ETHAmount)
      await DTT.approve(router.address, MaxUint256)

      await router.swapETHForExactTokens(outputAmount, [WETH.address, DTT.address], wallet.address, MaxUint256, {
        ...overrides,
        value: ETHAmount
      })

      it('amounts', async () => {
        await addLiquidity(DTTAmount, ETHAmount)
        await DTT.approve(router.address, MaxUint256)

        await expect(
          routerEventEmitter.swapETHForExactTokens(
            router.address,
            outputAmount,
            [WETH.address, DTT.address],
            wallet.address,
            MaxUint256,
            {
              ...overrides,
              value: ETHAmount
            }
          )
        )
          .to.emit(routerEventEmitter, 'Amounts')
          .withArgs([expectedSwapAmount, outputAmount])
      })
    })
  })
})
