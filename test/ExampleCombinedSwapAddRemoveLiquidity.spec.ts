import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { BigNumber } from 'ethers/utils'
import { MaxUint256 } from 'ethers/constants'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo18Decimals, mineBlock, encodePrice } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

import ExampleCombinedSwapAddRemoveLiquidity from '../build/ExampleCombinedSwapAddRemoveLiquidity.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe.only('ExampleCombinedSwapAddRemoveLiquidity', () => {
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

  describe('swapExactTokensAndAddLiquidity', () => {
    it('works with 5:10 token0:token1', async () => {
      await addLiquidity(expandTo18Decimals(5), expandTo18Decimals(10))
      expect(
        await combinedSwap.swapExactTokensAndAddLiquidity(
          token0.address, expandTo18Decimals(1),
          token1.address, expandTo18Decimals(1.5),
          wallet.address, MaxUint256
        )
      )
      // .to.emit(pair, '')
    })
  })
})
