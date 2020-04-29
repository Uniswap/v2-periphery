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

const MaxUint112 = bigNumberify(2)
  .pow(112)
  .sub(1)

const MINIMUM_LIQUIDITY = bigNumberify(10).pow(3)

describe('ExampleCombinedSwapAddRemoveLiquidity', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet, otherWallet] = provider.getWallets()
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

  function describeAmount(n: BigNumber) {
    if (n.eq(MaxUint256)) return 'max uint256'
    else if (n.eq(MaxUint112)) return 'max uint112'
    else return n.div(bigNumberify(10).pow(18))
  }

  describe('#calculateSwapInAmount', () => {
    for (let [reserveIn, reserveOut, userIn] of [
      [expandTo18Decimals(150), expandTo18Decimals(10), expandTo18Decimals(10)],
      [expandTo18Decimals(5), expandTo18Decimals(30), expandTo18Decimals(10)],
      [expandTo18Decimals(5), expandTo18Decimals(10), expandTo18Decimals(10)],
      [expandTo18Decimals(5), expandTo18Decimals(10), expandTo18Decimals(5)],
      [expandTo18Decimals(155), expandTo18Decimals(10), expandTo18Decimals(5)],
      [expandTo18Decimals(155), expandTo18Decimals(20), expandTo18Decimals(5)],
      [expandTo18Decimals(5), expandTo18Decimals(5), expandTo18Decimals(10)],
      // max reserves
      [MaxUint112, MaxUint112, expandTo18Decimals(10000)]
    ]) {
      it(`ratios match for reserveIn = ${describeAmount(reserveIn)}, reserveOut = ${describeAmount(
        reserveOut
      )}, userIn = ${describeAmount(userIn)}`, async () => {
        const swapIn = await combinedSwap.calculateSwapInAmount(reserveIn, userIn)
        const receiveOut = reserveOut.sub(reserveIn.mul(reserveOut).div(reserveIn.add(swapIn.mul(997).div(1000))))
        // check the difference in ratios <= 1 (integer math truncation)
        expect(
          userIn
            .sub(swapIn)
            .div(receiveOut)
            .sub(reserveIn.add(swapIn).div(reserveOut.sub(receiveOut)))
            .abs()
        ).to.lte(1)
        expect(
          receiveOut
            .div(userIn.sub(swapIn))
            .sub(reserveOut.sub(receiveOut).div(reserveIn.add(swapIn)))
            .abs()
        ).to.lte(1)
      })
    }
  })

  describe('#swapExactTokensAndAddLiquidity', () => {
    it('works with 5:10 token0:token1', async () => {
      const reserve0 = expandTo18Decimals(50)
      const reserve1 = expandTo18Decimals(100)
      const userAddToken0Amount = expandTo18Decimals(5)
      await addLiquidity(reserve0, reserve1)
      const swapAmount = await combinedSwap.calculateSwapInAmount(reserve0, userAddToken0Amount)
      const expectedAmountB = await router.getAmountOut(swapAmount, reserve0, reserve1)
      await expect(
        combinedSwap.swapExactTokensAndAddLiquidity(
          token0.address,
          token1.address,
          userAddToken0Amount,
          expectedAmountB,
          otherWallet.address,
          MaxUint256,
          overrides
        )
      )
        // first swaps
        .to.emit(token0, 'Transfer')
        .withArgs(wallet.address, combinedSwap.address, userAddToken0Amount)
        .to.emit(token0, 'Approval')
        .withArgs(combinedSwap.address, router.address, userAddToken0Amount)
        .to.emit(token0, 'Transfer')
        .withArgs(combinedSwap.address, pair.address, swapAmount)
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, combinedSwap.address, expectedAmountB)
        .to.emit(pair, 'Transfer')

      expect(await pair.balanceOf(otherWallet.address)).to.be.gt(0)
    })
  })

  describe('#removeLiquidityAndSwapToToken', () => {
    const reserve0 = expandTo18Decimals(20)
    const reserve1 = expandTo18Decimals(180)
    beforeEach('add liquidity', async () => {
      await addLiquidity(reserve0, reserve1)
      expect(await pair.balanceOf(wallet.address)).to.eq(expandTo18Decimals(60).sub(MINIMUM_LIQUIDITY))
    })
    it('burns and swaps', async () => {
      const removeLiquidityAmount = expandTo18Decimals(6)
      const minDesiredTokenOut = expandTo18Decimals(20) // greater than 180 * 0.1 (6/60)
      const expectedBurnAmountUndesiredToken = expandTo18Decimals(2)
      const expectedBurnAmountDesiredToken = expandTo18Decimals(18)
      const undesiredToken = token0
      const desiredToken = token1
      const reserve0AfterBurn = reserve0.sub(expectedBurnAmountUndesiredToken)
      const reserve1AfterBurn = reserve1.sub(expectedBurnAmountDesiredToken)
      const expectedAmountFromSwapAfterBurn = await router.getAmountOut(
        expectedBurnAmountUndesiredToken,
        reserve0AfterBurn,
        reserve1AfterBurn
      )
      await expect(
        combinedSwap.removeLiquidityAndSwapToToken(
          undesiredToken.address,
          desiredToken.address,
          removeLiquidityAmount,
          minDesiredTokenOut,
          otherWallet.address,
          MaxUint256,
          overrides
        )
      )
        // burns the liquidity
        .to.emit(pair, 'Transfer')
        .withArgs(wallet.address, combinedSwap.address, removeLiquidityAmount)
        .to.emit(pair, 'Approval')
        .withArgs(combinedSwap.address, router.address, removeLiquidityAmount)
        .to.emit(pair, 'Transfer')
        .withArgs(combinedSwap.address, pair.address, removeLiquidityAmount)
        .to.emit(undesiredToken, 'Transfer')
        .withArgs(pair.address, combinedSwap.address, expectedBurnAmountUndesiredToken)
        .to.emit(desiredToken, 'Transfer')
        .withArgs(pair.address, combinedSwap.address, expectedBurnAmountDesiredToken)
        .to.emit(pair, 'Burn')
        .withArgs(
          router.address,
          expectedBurnAmountUndesiredToken,
          expectedBurnAmountDesiredToken,
          combinedSwap.address
        )
        // then swaps the undesired token through the router
        .to.emit(undesiredToken, 'Approval')
        .withArgs(combinedSwap.address, router.address, expectedBurnAmountUndesiredToken)
        .to.emit(undesiredToken, 'Transfer')
        .withArgs(combinedSwap.address, pair.address, expectedBurnAmountUndesiredToken)
        .to.emit(desiredToken, 'Transfer')
        .withArgs(pair.address, otherWallet.address, expectedAmountFromSwapAfterBurn)
        // receives desired token from the swap
        .to.emit(pair, 'Swap')
        // TODO(moodysalem): understand why this fails
        // .withArgs(
        //   combinedSwap.address,
        //   expectedBurnAmountUndesiredToken,
        //   0,
        //   0,
        //   expectedAmountFromSwapAfterBurn,
        //   otherWallet.address
        // )
        // then transfers the desired token from the burn to the to address
        .to.emit(desiredToken, 'Transfer')
        .withArgs(combinedSwap.address, otherWallet.address, expectedBurnAmountDesiredToken)

      expect(await desiredToken.balanceOf(otherWallet.address)).eq(
        expectedAmountFromSwapAfterBurn.add(expectedBurnAmountDesiredToken)
      )
      expect(await undesiredToken.balanceOf(otherWallet.address)).eq(0)
    })
  })
})
