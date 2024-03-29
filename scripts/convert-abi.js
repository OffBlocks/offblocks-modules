async function main() {
  const jsonAbi =
    require("../artifacts/erc7579/interfaces/IERC7579Account.sol/IERC7579Account.json").abi;

  const iface = new ethers.Interface(jsonAbi);
  console.log(iface.format(true));
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
