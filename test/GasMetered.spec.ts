import chai, { expect } from 'chai'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'
import { Wallet } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { BigNumber, solidityKeccak256, arrayify } from 'ethers/utils'
import GasMetered from '../build/GasMeteredImpl.json'
import ERC20 from '../build/ERC20.json'
import { expandTo18Decimals } from './shared/utilities'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

describe('GasMetered', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const wallets = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, wallets)

  async function gasMeteredFixture(provider: Web3Provider, [admin, relayer, user]: Wallet[]) {
    const gasMetered = await deployContract(admin, GasMetered, [expandTo18Decimals(10), expandTo18Decimals(1)])
    const balanceStart = '1000000000000000'
    const erc20 = await deployContract(admin, ERC20, [new BigNumber(balanceStart)])
    await erc20.functions.transfer(user.address, new BigNumber(balanceStart))
    await erc20.connect(user).functions.approve(gasMetered.address, balanceStart)

    return {
      gasMetered,
      admin,
      relayer,
      user,
      erc20,
      balanceStart
    }
  }

  it('gasMetered', async () => {
    const { gasMetered, relayer, user, erc20, balanceStart } = await loadFixture(gasMeteredFixture)

    const incrementData = gasMetered.interface.functions.increment.encode([])
    const gasPayer = relayer.address
    const gasOverhead = new BigNumber(10)
    const token = erc20.address
    const signer = user.address
    const nonce = new BigNumber(1)

    const gasRefund = {
      gasPayer: gasPayer,
      gasOverhead: gasOverhead,
      token: token
    }

    const replayProtection = {
      signer: signer,
      nonce: nonce
    }

    const chainId = await gasMetered.functions.getChainID()

    // data,
    // gasRefund.gasPayer,
    // gasRefund.gasOverhead,
    // gasRefund.token,
    // replayProtection.signer,
    // replayProtection.nonce,
    // getChainID(),
    // address(this)
    const h = solidityKeccak256(
      ['bytes', 'address', 'uint256', 'address', 'address', 'uint256', 'uint256', 'address'],
      [incrementData, relayer.address, gasOverhead, token, signer, nonce, chainId, gasMetered.address]
    )

    const signature = await user.signMessage(arrayify(h))
    const userBalanceBefore = (await erc20.functions.balanceOf(user.address)) as BigNumber
    const relayerBalanceBefore = (await erc20.functions.balanceOf(relayer.address)) as BigNumber
    const valBefore = (await gasMetered.functions.val()) as BigNumber

    expect(userBalanceBefore.toString(), 'user balance before').to.eq(balanceStart)
    expect(relayerBalanceBefore.toString(), 'relayer balance before').to.eq('0')
    expect(valBefore.toString(), 'val before').to.eq('0')

    await gasMetered.functions.gasMetered(incrementData, gasRefund, {
      ...replayProtection,
      signature
    })

    const userBalanceAfter = (await erc20.functions.balanceOf(user.address)) as BigNumber
    const relayerBalanceAfter = (await erc20.functions.balanceOf(relayer.address)) as BigNumber
    const valAfter = (await gasMetered.functions.val()) as BigNumber

    expect(userBalanceAfter.toNumber(), 'user balance after').to.lt(parseInt(balanceStart))
    expect(relayerBalanceAfter.toNumber(), 'relayer balance after').to.gt(0)
    expect(valAfter.toString(), 'val after').to.eq('1')
  })
})
