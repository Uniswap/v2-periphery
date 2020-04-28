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
    combinedSwap = await deployContract(
      wallet,
      ExampleCombinedSwapAddRemoveLiquidity,
      [fixture.factoryV2.address, fixture.router.address],
      overrides
    )
  })

  beforeEach('approve transfers to combined swap', async () => {
    await token0.approve(combinedSwap.address, MaxUint256)
    await token1.approve(combinedSwap.address, MaxUint256)
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
      expect(await combinedSwap.calculateSwapInAmount(bigNumberify(2).pow(112).sub(1), expandTo18Decimals(10000))).to.eq(
        '5007511266897939502255' // 5k tokens
      )
    })
  })

  describe('#swapExactTokensAndAddLiquidity', () => {
    it.only('works with 5:10 token0:token1', async () => {
      await addLiquidity(expandTo18Decimals(50), expandTo18Decimals(100))
      expect(
        await combinedSwap.swapExactTokensAndAddLiquidity(
          token0.address,
          token1.address,
          expandTo18Decimals(5),
          0,
          wallet.address,
          MaxUint256
        )
      )
      // .to.emit(pair, '')
    })
  })

  describe('#removeLiquidityAndSwapToToken', () => {
    beforeEach('add liquidity', () => {
      // results in 5 lp tokens
      addLiquidity(expandTo18Decimals(4), expandTo18Decimals(3))
    })
    it('burns and swaps', async () => {
      await expect(
        combinedSwap.removeLiquidityAndSwapToToken(
          token0.address, token1.address,
          expandTo18Decimals(2),
          /* 3 * (2/5) + (4*2/5) swapped in = 1.6, so let's say minimum out of 1.2 + 1 = 2 */
          expandTo18Decimals(2),
          wallet.address,
          MaxUint256
        )
      )
        .to.emit(pair, 'Transfer')
        .withArgs(wallet.address, pair.address, 2)
    })
  })
})
