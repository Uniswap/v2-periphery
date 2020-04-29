import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { bigNumberify } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals, mineBlock, encodePrice } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import ExampleSlidingWindowOracle from '../build/ExampleSlidingWindowOracle.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

const token0Amount = expandTo18Decimals(5)
const token1Amount = expandTo18Decimals(10)

describe('ExampleSlidingWindowOracle', () => {
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
  let weth: Contract
  let slidingWindowOracle: Contract

  async function addLiquidity() {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(wallet.address, overrides)
  }

  const period = 86400
  const numBuckets = 24

  function observationIndex(timestamp: number): number {
    return Math.floor((timestamp % period) / (period / numBuckets))
  }

  beforeEach('deploy fixture', async function() {
    const fixture = await loadFixture(v2Fixture)

    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    weth = fixture.WETH

    slidingWindowOracle = await deployContract(
      wallet,
      ExampleSlidingWindowOracle,
      [fixture.factoryV2.address, period, numBuckets],
      overrides
    )
  })

  beforeEach('add liquidity', addLiquidity)

  describe('#update', () => {
    it('succeeds', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
    })

    it('sets the appropriate epoch slot', async () => {
      const blockTimestamp = (await pair.getReserves())[2]
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      expect(await slidingWindowOracle.pairObservations(pair.address, observationIndex(blockTimestamp))).to.deep.eq([
        blockTimestamp,
        await pair.price0CumulativeLast(),
        await pair.price1CumulativeLast()
      ])
    }).retries(2) // we may have slight differences between pair blockTimestamp and the expected timestamp
    // because the previous block timestamp may differ from the current block timestamp by 1 second

    it('gas for first update (allocates empty array)', async () => {
      const tx = await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('117730')
    }).retries(2) // gas test inconsistent

    it('gas for second update', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const tx = await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('34052')
    }).retries(2) // gas test inconsistent

    it('pair not exists', async () => {
      await expect(slidingWindowOracle.update(weth.address, token1.address)).to.be.reverted
    })
  })

  describe('#consult', () => {
    it('fails if previous bucket not set', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      await expect(slidingWindowOracle.consult(token0.address, 0, token1.address)).to.be.revertedWith(
        'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION'
      )
    })

    describe('happy path', () => {
      let blockTimestamp: number
      let previousBlockTimestamp: number
      let previousCumulativePrices: any
      beforeEach('add some prices', async () => {
        previousBlockTimestamp = (await pair.getReserves())[2]
        previousCumulativePrices = [await pair.price0CumulativeLast(), await pair.price1CumulativeLast()]
        await slidingWindowOracle.update(token0.address, token1.address, overrides)
        blockTimestamp = previousBlockTimestamp + 60 * 60 * 23
        await mineBlock(provider, blockTimestamp)
        await slidingWindowOracle.update(token0.address, token1.address, overrides)
      })

      it('has cumulative price in previous bucket', async () => {
        expect(
          await slidingWindowOracle.pairObservations(pair.address, observationIndex(previousBlockTimestamp))
        ).to.deep.eq([previousBlockTimestamp, previousCumulativePrices[0], previousCumulativePrices[1]])
      })

      it('has cumulative price in current bucket', async () => {
        const timeElapsed = blockTimestamp - previousBlockTimestamp
        const prices = encodePrice(token0Amount, token1Amount)
        expect(await slidingWindowOracle.pairObservations(pair.address, observationIndex(blockTimestamp))).to.deep.eq([
          blockTimestamp,
          prices[0].mul(timeElapsed),
          prices[1].mul(timeElapsed)
        ])
      }).retries(5) // test flaky because timestamps aren't mocked

      it('pair not exists', async () => {
        await expect(slidingWindowOracle.consult(weth.address, 0, token1.address)).to.be.reverted
      })

      it('provides the current ratio in consult token0', async () => {
        expect(await slidingWindowOracle.consult(token0.address, 100, token1.address)).to.eq(200)
      })

      it('provides the current ratio in consult token1', async () => {
        expect(await slidingWindowOracle.consult(token1.address, 100, token0.address)).to.eq(50)
      })
    })
  })
})
