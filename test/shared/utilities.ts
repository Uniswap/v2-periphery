import { providers } from 'ethers'
import { BigNumber, bigNumberify } from 'ethers/utils'

export function expandTo18Decimals(n: number): BigNumber {
  return bigNumberify(n).mul(bigNumberify(10).pow(18))
}

async function mineBlock(provider: providers.Web3Provider, timestamp?: number): Promise<void> {
  await new Promise((resolve, reject) => {
    ;(provider._web3Provider.sendAsync as any)(
      { jsonrpc: '2.0', method: 'evm_mine', params: timestamp ? [timestamp] : [] },
      (error: any, result: any): void => {
        if (error) {
          reject(error)
        } else {
          resolve(result)
        }
      }
    )
  })
}

export async function mineBlocks(
  provider: providers.Web3Provider,
  numberOfBlocks: number,
  timestamp?: number
): Promise<void> {
  await Promise.all([...Array(numberOfBlocks - 1)].map(() => mineBlock(provider)))
  await mineBlock(provider, timestamp)
}
