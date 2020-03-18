import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { BigNumber } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals, mineBlock, encodePrice } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import ExampleOracle from '../build/ExampleOracle.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe('ExampleOracle', () => {
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
  let oracleExample: Contract
  beforeEach(async function() {
    const fixture = await loadFixture(v2Fixture)

    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    oracleExample = await deployContract(wallet, ExampleOracle, [pair.address], overrides)
  })

  async function addLiquidity(token0Amount: BigNumber, token1Amount: BigNumber) {
    await token0.transfer(pair.address, token0Amount)
    await token1.transfer(pair.address, token1Amount)
    await pair.mint(wallet.address, overrides)
  }

  it('initialize', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)

    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 1)
    await pair.sync(overrides)
    await oracleExample.initialize(overrides)
  })

  it('update', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 1)
    await pair.sync(overrides)
    await oracleExample.initialize(overrides)
    await mineBlock(provider, blockTimestamp + 2)
    await oracleExample.update(overrides)

    const expectedPrice = encodePrice(token0Amount, token1Amount)

    expect(await oracleExample.price0Average()).to.eq(expectedPrice[0])
    expect(await oracleExample.price1Average()).to.eq(expectedPrice[1])
  })

  it('quote0, quote1', async () => {
    const token0Amount = expandTo18Decimals(5)
    const token1Amount = expandTo18Decimals(10)
    await addLiquidity(token0Amount, token1Amount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 1)
    await pair.sync(overrides)
    await oracleExample.initialize(overrides)
    await mineBlock(provider, blockTimestamp + 2)
    await oracleExample.update(overrides)

    expect(await oracleExample.quote(token0.address, token0Amount)).to.eq(token1Amount)
    expect(await oracleExample.quote(token1.address, token1Amount)).to.eq(token0Amount)
  })
})
