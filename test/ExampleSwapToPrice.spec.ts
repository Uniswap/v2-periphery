import chai, {expect} from 'chai'
import {Contract} from 'ethers'
import {MaxUint256} from 'ethers/constants'
import {BigNumber, bigNumberify, defaultAbiCoder, formatEther} from 'ethers/utils'
import {solidity, MockProvider, createFixtureLoader, deployContract} from 'ethereum-waffle'

import {expandTo18Decimals} from './shared/utilities'
import {v2Fixture} from './shared/fixtures'

import ExampleSwapToPrice from '../build/ExampleSwapToPrice.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe('ExampleSwapToPrice', () => {
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
  let swapToPriceExample: Contract
  let router: Contract
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)
    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    router = fixture.router
    swapToPriceExample = await deployContract(wallet, ExampleSwapToPrice, [fixture.router.address], overrides)
  })

  beforeEach('set up price differential of 1:100', async () => {
    await token0.transfer(pair.address, expandTo18Decimals(10))
    await token1.transfer(pair.address, expandTo18Decimals(1000))
    await pair.sync(overrides)
  })

  beforeEach('approve the swap contract to spend any amount of both tokens', async () => {
    await token0.approve(swapToPriceExample.address, MaxUint256)
    await token1.approve(swapToPriceExample.address, MaxUint256)
  })

  it('correct router address', async () => {
    expect(await swapToPriceExample.router()).to.eq(router.address)
  })

  describe('#swapToPrice', () => {
    it('requires non-zero true price inputs', async () => {
      await expect(
        swapToPriceExample.swapToPrice(
          token0.address,
          token1.address,
          MaxUint256,
          MaxUint256,
          0,
          0,
          wallet.address,
          MaxUint256
        )
      ).to.be.revertedWith('ExampleSwapToPrice: ZERO_PRICE')
      await expect(
        swapToPriceExample.swapToPrice(
          token0.address,
          token1.address,
          MaxUint256,
          MaxUint256,
          10,
          0,
          wallet.address,
          MaxUint256
        )
      ).to.be.revertedWith('ExampleSwapToPrice: ZERO_PRICE')
      await expect(
        swapToPriceExample.swapToPrice(
          token0.address,
          token1.address,
          MaxUint256,
          MaxUint256,
          0,
          10,
          wallet.address,
          MaxUint256
        )
      ).to.be.revertedWith('ExampleSwapToPrice: ZERO_PRICE')
    })

    it('moves the price to 1:90', async () => {
      await expect(
        swapToPriceExample.swapToPrice(
          token0.address,
          token1.address,
          MaxUint256,
          MaxUint256,
          1,
          90,
          wallet.address,
          MaxUint256,
          overrides
        )
      )
        .to.emit(token0, 'Transfer')
        .withArgs(wallet.address, swapToPriceExample.address, '526682316179835569')
        .to.emit(token0, 'Approval')
        .withArgs(swapToPriceExample.address, router.address, '526682316179835569')
        .to.emit(token0, 'Transfer')
        .withArgs(swapToPriceExample.address, pair.address, '526682316179835569')
        .to.emit(token1, 'Transfer')
        .withArgs(pair.address, wallet.address, '49890467170695440744')
    })

    it('moves the price to 1:110', async () => {
      await expect(
        swapToPriceExample.swapToPrice(
          token0.address,
          token1.address,
          MaxUint256,
          MaxUint256,
          1,
          110,
          wallet.address,
          MaxUint256,
          overrides
        )
      )
        // (1e21 + 47376582963642643588) : (1e19 - 451039908682851138) ~= 1:110
        .to.emit(token1, 'Transfer')
        .withArgs(wallet.address, swapToPriceExample.address, '47376582963642643588')
        .to.emit(token1, 'Approval')
        .withArgs(swapToPriceExample.address, router.address, '47376582963642643588')
        .to.emit(token1, 'Transfer')
        .withArgs(swapToPriceExample.address, pair.address, '47376582963642643588')
        .to.emit(token0, 'Transfer')
        .withArgs(pair.address, wallet.address, '451039908682851138')
    })

    it('swap gas cost', async () => {
      const tx = await swapToPriceExample.swapToPrice(
        token0.address,
        token1.address,
        MaxUint256,
        MaxUint256,
        1,
        110,
        wallet.address,
        MaxUint256,
        overrides
      )
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('124045')
    })
  })
})
