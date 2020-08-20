import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { MaxUint256 } from 'ethers/constants'
import { BigNumber, bigNumberify, defaultAbiCoder, formatEther } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import ExampleComputeLiquidityValue from '../build/ExampleComputeLiquidityValue.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe.only('ExampleComputeLiquidityValue', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token0: Contract
  let token1: Contract
  let factory: Contract
  let pair: Contract
  let computeLiquidityValue: Contract
  beforeEach(async function () {
    const fixture = await loadFixture(v2Fixture)
    token0 = fixture.token0
    token1 = fixture.token1
    pair = fixture.pair
    factory = fixture.factoryV2
    computeLiquidityValue = await deployContract(
      wallet,
      ExampleComputeLiquidityValue,
      [fixture.factoryV2.address],
      overrides
    )
  })

  beforeEach('mint some liquidity for the pair at 1:100 (100 shares minted)', async () => {
    await token0.transfer(pair.address, expandTo18Decimals(10))
    await token1.transfer(pair.address, expandTo18Decimals(1000))
    await pair.mint(wallet.address, overrides)
    expect(await pair.totalSupply()).to.eq(expandTo18Decimals(100))
  })

  it('correct factory address', async () => {
    expect(await computeLiquidityValue.factory()).to.eq(factory.address)
  })

  describe('fee is off', () => {
    it('produces the correct value after arbing to 1:105', async () => {
      const [tokenAAmount, tokenBAmount] = await computeLiquidityValue.getLiquidityValueAfterArbitrageToPrice(token0.address, token1.address, 1, 105, expandTo18Decimals(5))
      expect(tokenAAmount).to.eq('488683612488266114') // slightly less than 5% of 10, or 0.5
      expect(tokenBAmount).to.eq('51161327957205755422') // slightly more than 5% of 100, or 5
    })

    it('produces the correct value after arbing to 1:95', async () => {
      const [tokenAAmount, tokenBAmount] = await computeLiquidityValue.getLiquidityValueAfterArbitrageToPrice(token0.address, token1.address, 1, 95, expandTo18Decimals(5))
      expect(tokenAAmount).to.eq('512255881944227034') // slightly more than 5% of 10, or 0.5
      expect(tokenBAmount).to.eq('48807237571060645526') // slightly less than 5% of 100, or 5
    })

    it('produces correct value at the current price', async () => {
      const [tokenAAmount, tokenBAmount] = await computeLiquidityValue.getLiquidityValueAfterArbitrageToPrice(token0.address, token1.address, 1, 100, expandTo18Decimals(5))
      expect(tokenAAmount).to.eq('500000000000000000') // slightly more than 5% of 10, or 0.5
      expect(tokenBAmount).to.eq('50000000000000000000') // slightly less than 5% of 100, or 5
    })
  })

  describe('fee is on', () => {
    it('produces the correct value after arbing to 1:105')
    it('produces the correct value after arbing to 1:95')
    it('produces correct value at the current price')
  })
})
