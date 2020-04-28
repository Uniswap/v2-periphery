import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { BigNumber } from 'ethers/utils'
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

describe.only('ExampleSlidingWindowOracle', () => {
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
  let slidingWindowOracle: Contract

  async function addLiquidity() {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(wallet.address, overrides)
  }

  beforeEach('deploy fixture', async function() {
    const fixture = await loadFixture(v2Fixture)

    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair

    slidingWindowOracle = await deployContract(
      wallet,
      ExampleSlidingWindowOracle,
      [fixture.factoryV2.address, 86400, 24],
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
      const slot = blockTimestamp /
      expect(await slidingWindowOracle.pairPriceData(pair.address, ))
        .to.eq([])
    })

    it('gas', async () => {
      const tx = await slidingWindowOracle.update(token0.address, token1.address, overrides)
      const receipt = await tx.wait()
      expect(receipt.gasUsed).to.eq('176053')
    })
  })
})
