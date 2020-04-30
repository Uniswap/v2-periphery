import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { bigNumberify } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals, mineBlock, encodePrice, increaseTime } from './shared/utilities'
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
  let factory: Contract

  async function addLiquidity() {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(wallet.address, overrides)
  }

  const defaultWindowSize = 86400 // 24 hours
  const defaultGranularity = 24 // 1 hour each

  function observationIndexOf(
    timestamp: number,
    windowSize: number = defaultWindowSize,
    granularity: number = defaultGranularity
  ): number {
    const periodSize = Math.floor(windowSize / granularity)
    const epochPeriod = Math.floor(timestamp / periodSize)
    return epochPeriod % granularity
  }

  function deployOracle(windowSize: number, granularity: number) {
    return deployContract(wallet, ExampleSlidingWindowOracle, [factory.address, windowSize, granularity], overrides)
  }

  beforeEach('deploy fixture', async function() {
    const fixture = await loadFixture(v2Fixture)

    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    weth = fixture.WETH
    factory = fixture.factoryV2
  })

  beforeEach('add liquidity', addLiquidity)

  it('requires granularity to be greater than 0', async () => {
    await expect(deployOracle(defaultWindowSize, 0)).to.be.revertedWith('SlidingWindowOracle: GRANULARITY')
  })

  it('requires windowSize to be evenly divisible by granularity', async () => {
    await expect(deployOracle(defaultWindowSize - 1, defaultGranularity)).to.be.revertedWith(
      'SlidingWindowOracle: WINDOW_NOT_EVENLY_DIVISIBLE'
    )
  })

  it('computes the periodSize correctly', async () => {
    const oracle = await deployOracle(defaultWindowSize, defaultGranularity)
    expect(await oracle.periodSize()).to.eq(3600)
    const oracleOther = await deployOracle(defaultWindowSize * 2, defaultGranularity / 2)
    expect(await oracleOther.periodSize()).to.eq(3600 * 4)
  })

  describe('#observationIndexOf', () => {
    it('works for examples', async () => {
      const oracle = await deployOracle(defaultWindowSize, defaultGranularity)
      expect(await oracle.observationIndexOf(0)).to.eq(0)
      expect(await oracle.observationIndexOf(3599)).to.eq(0)
      expect(await oracle.observationIndexOf(3600)).to.eq(1)
      expect(await oracle.observationIndexOf(4800)).to.eq(1)
      expect(await oracle.observationIndexOf(7199)).to.eq(1)
      expect(await oracle.observationIndexOf(7200)).to.eq(2)
      expect(await oracle.observationIndexOf(86399)).to.eq(23)
      expect(await oracle.observationIndexOf(86400)).to.eq(0)
      expect(await oracle.observationIndexOf(90000)).to.eq(1)
    })
    it('matches offline computation', async () => {
      const oracle = await deployOracle(defaultWindowSize, defaultGranularity)
      for (let timestamp of [0, 5000, 1000, 25000, 86399, 86400, 86401]) {
        expect(await oracle.observationIndexOf(timestamp)).to.eq(observationIndexOf(timestamp))
      }
    })
  })

  describe('#update', () => {
    let slidingWindowOracle: Contract

    beforeEach(
      'deploy oracle',
      async () => (slidingWindowOracle = await deployOracle(defaultWindowSize, defaultGranularity))
    )

    beforeEach('set start time to 0', () => mineBlock(provider, 0))

    it('succeeds', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
    })

    it('sets the appropriate epoch slot', async () => {
      const blockTimestamp = (await pair.getReserves())[2]
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      expect(await slidingWindowOracle.pairObservations(pair.address, observationIndexOf(blockTimestamp))).to.deep.eq([
        bigNumberify(blockTimestamp),
        await pair.price0CumulativeLast(),
        await pair.price1CumulativeLast()
      ])
    }).retries(2) // we may have slight differences between pair blockTimestamp and the expected timestamp
    // because the previous block timestamp may differ from the current block timestamp by 1 second

    it('gas for first update (allocates empty array)', async () => {
      const tx = await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('116816')
    }).retries(2) // gas test inconsistent

    it('gas for second update in the same period (skips)', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const tx = await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('25574')
    }).retries(2) // gas test inconsistent

    it('gas for second update different period (no allocate, no skip)', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      expect(await increaseTime(provider, 3600)).to.eq(3600)
      const tx = await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('94542')
    }).retries(2) // gas test inconsistent

    it('fails for invalid pair', async () => {
      await expect(slidingWindowOracle.update(weth.address, token1.address)).to.be.reverted
    })
  })

  describe('#consult', () => {
    let slidingWindowOracle: Contract

    beforeEach(
      'deploy oracle',
      async () => (slidingWindowOracle = await deployOracle(defaultWindowSize, defaultGranularity))
    )

    beforeEach('set start time to 0', () => mineBlock(provider, 0))

    it('fails if previous bucket not set', async () => {
      await slidingWindowOracle.update(token0.address, token1.address, overrides)
      await expect(slidingWindowOracle.consult(token0.address, 0, token1.address)).to.be.revertedWith(
        'SlidingWindowOracle: MISSING_HISTORICAL_OBSERVATION'
      )
    })

    it('fails for invalid pair', async () => {
      await expect(slidingWindowOracle.consult(weth.address, 0, token1.address)).to.be.reverted
    })

    describe('happy path', () => {
      let blockTimestamp: number
      let previousBlockTimestamp: number
      let previousCumulativePrices: any
      beforeEach('add some prices', async () => {
        previousBlockTimestamp = (await pair.getReserves())[2]
        previousCumulativePrices = [await pair.price0CumulativeLast(), await pair.price1CumulativeLast()]
        await slidingWindowOracle.update(token0.address, token1.address, overrides)
        blockTimestamp = (await increaseTime(provider, 23 * 3600)) + previousBlockTimestamp
        await slidingWindowOracle.update(token0.address, token1.address, overrides)
      })

      it('has cumulative price in previous bucket', async () => {
        expect(
          await slidingWindowOracle.pairObservations(pair.address, observationIndexOf(previousBlockTimestamp))
        ).to.deep.eq([bigNumberify(previousBlockTimestamp), previousCumulativePrices[0], previousCumulativePrices[1]])
      }).retries(5) // test flaky because timestamps aren't mocked

      it('has cumulative price in current bucket', async () => {
        const timeElapsed = blockTimestamp - previousBlockTimestamp
        const prices = encodePrice(token0Amount, token1Amount)
        expect(
          await slidingWindowOracle.pairObservations(pair.address, observationIndexOf(blockTimestamp))
        ).to.deep.eq([bigNumberify(blockTimestamp), prices[0].mul(timeElapsed), prices[1].mul(timeElapsed)])
      }).retries(5) // test flaky because timestamps aren't mocked

      it('provides the current ratio in consult token0', async () => {
        expect(await slidingWindowOracle.consult(token0.address, 100, token1.address)).to.eq(200)
      })

      it('provides the current ratio in consult token1', async () => {
        expect(await slidingWindowOracle.consult(token1.address, 100, token0.address)).to.eq(50)
      })
    })
  })
})
