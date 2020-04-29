import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'
import { MaxUint256 } from 'ethers/constants'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import ExampleCombinedSwapAddRemoveLiquidity from '../build/ExampleCombinedSwapAddRemoveLiquidity.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

describe('ExampleCombinedSwapAddRemoveLiquidity', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token0: Contract
  let token1: Contract
  let pair: Contract
  let router: Contract
  let combinedSwap: Contract

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(wallet.address, overrides)
  }

  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    router = fixture.router
    combinedSwap = await deployContract(
      wallet,
      ExampleCombinedSwapAddRemoveLiquidity,
      [fixture.factoryV2.address, fixture.router.address],
      overrides
    )
  })

  beforeEach('approve transfers of all tokens to combined swap', async () => {
    await token0.approve(combinedSwap.address, MaxUint256)
    await token1.approve(combinedSwap.address, MaxUint256)
    await pair.approve(combinedSwap.address, MaxUint256)
  })

  describe('#calculateSwapInAmount', () => {
    it('X0 == 150 and Xin = 10', async () => {
      expect(await combinedSwap.calculateSwapInAmount(expandTo18Decimals(150), expandTo18Decimals(10))).to.eq(
        '4926724110726670487'
      )
    })
    it('X0 == 5 and Xin = 10', async () => {
      expect(await combinedSwap.calculateSwapInAmount(expandTo18Decimals(5), expandTo18Decimals(10))).to.eq(
        '3665754415082470298'
      )
    })

    it('works with max reserves and 10k tokens', async () => {
      expect(
        await combinedSwap.calculateSwapInAmount(
          bigNumberify(2)
            .pow(112)
            .sub(1),
          expandTo18Decimals(10000)
        )
      ).to.eq(
        '5007511266897939502255' // 5k tokens
      )
    })
  })

  describe('#swapExactTokensAndAddLiquidity', () => {
    it('works with 5:10 token0:token1', async () => {
      const reserve0 = expandTo18Decimals(50)
      const reserve1 = expandTo18Decimals(100)
      const k0 = reserve0.mul(reserve1)
      const userAddToken0Amount = expandTo18Decimals(5)
      await addLiquidity(reserve0, reserve1)
      const swapAmount = await combinedSwap.calculateSwapInAmount(reserve0, userAddToken0Amount)
      const expectedAmountB = reserve1.sub(k0.div(reserve0.add(swapAmount.mul(997).div(1000))))
      await expect(
        combinedSwap.swapExactTokensAndAddLiquidity(
          token0.address,
          token1.address,
          userAddToken0Amount,
          expectedAmountB,
          wallet.address,
          MaxUint256
        )
      )
        .to.emit(token0, 'Transfer')
        .withArgs(wallet.address, combinedSwap.address, userAddToken0Amount)
        .to.emit(token0, 'Approval')
        .withArgs(combinedSwap.address, router.address, userAddToken0Amount)
        .to.emit(token0, 'Transfer')
        .withArgs(combinedSwap.address, pair.address, swapAmount)
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, combinedSwap.address, expectedAmountB.add(1))
    })
  })

  describe('#removeLiquidityAndSwapToToken', () => {
    beforeEach('add liquidity', async () => {
      await addLiquidity(expandTo18Decimals(20), expandTo18Decimals(180))
      expect(await pair.balanceOf(wallet.address)).to.eq(expandTo18Decimals(60).sub(MINIMUM_LIQUIDITY))
    })
    it('burns and swaps', async () => {
      const removeLiquidityAmount = expandTo18Decimals(6)
      const minToken1Out = expandTo18Decimals(20) // greater than 180 * 0.1 (6/60)
      await expect(
        combinedSwap.removeLiquidityAndSwapToToken(
          token0.address,
          token1.address,
          removeLiquidityAmount,
          minToken1Out,
          wallet.address,
          MaxUint256
        )
      )
        .to.emit(pair, 'Transfer')
        .withArgs(wallet.address, pair.address, removeLiquidityAmount)
    })
  })
})
