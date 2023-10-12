const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Deploying contracts with the account:", deployer.address);

  const FACTORY_ADDRESS = "0xc7a91efdD0f90A420fcAF11433C63B2cd59222FA";
  const WETH_ADDRESS = "0xb8f2E6a025C3dA0f8D14D20B8Ed0d1d7ac35E64c";

  const UniswapV2Router01 = await hre.ethers.getContractFactory("UniswapV2Router01");
  const router = await UniswapV2Router01.deploy(FACTORY_ADDRESS, WETH_ADDRESS);
  
  await router.deployed();
  
  console.log("UniswapV2Router01 deployed to:", router.address);

  // Verify the contract on Etherscan
  await hre.run("verify:verify", {
    address: router.address,
    constructorArguments: [FACTORY_ADDRESS, deployer.address],
  });
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
