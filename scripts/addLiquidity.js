const { ethers } = require("hardhat");

async function main() {
  const routerAddress = "0x17eF81Ba65De3b850777C6bdD2cDfe3028c6B2Eb";
  const tokenA = "0x4b3eed833746afdda8bea073bb0edb2db9c0ae40";
  const tokenB = "0x8040905aa2275a97b693bfc37803c52c132e34eb";
  const amountADesired = '2000000000000000000';
  const amountBDesired = '2000000000000000000';
  const amountAMin = '1000000000000000000';
  const amountBMin = '1000000000000000000';
  const toAddress = "0x497CB171dDF49af82250D7723195D7E47Ca38A95";
  const deadline = '1797114599';

  const router = await ethers.getContractAt("UniswapV2Router01", routerAddress);
  const [signer] = await ethers.getSigners();

  console.log("Signer address:", signer.address);

  const tx = await router.addLiquidity(
    tokenA,
    tokenB,
    amountADesired,
    amountBDesired,
    amountAMin,
    amountBMin,
    toAddress,
    deadline,
    {
      gasLimit: 3000000,
      from: signer.address,
    }
  );

  console.log("Transaction:", tx);
  const receipt = await tx.wait();

  console.log(`Transaction mined: ${receipt.transactionHash}`);
  console.log(`Block number: ${receipt.blockNumber}`);
  console.log(`From address: ${receipt.from}`);
  console.log(`To address: ${receipt.to}`);
  console.log(`Gas used: ${receipt.gasUsed}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
