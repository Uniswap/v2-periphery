const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploying contracts with the account:", deployer.address);

  const FACTORY_ADDRESS = "0x0b69664b59333dA2217A963f6eFf67b10d6E2742";
  const WETH_ADDRESS = "0xb8f2E6a025C3dA0f8D14D20B8Ed0d1d7ac35E64c";

  const UniswapV2Router02 = await hre.ethers.getContractFactory("UniswapV2Router02");
  const router = await UniswapV2Router02.deploy(FACTORY_ADDRESS, WETH_ADDRESS);

  await router.deployed();

  console.log("UniswapV2Router02 deployed to:", router.address);

  // Verify the contract on Etherscan (comment out if not needed)
  // await hre.run("verify:verify", {
  //   address: router.address,
  //   constructorArguments: [FACTORY_ADDRESS, WETH_ADDRESS],
  // });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
