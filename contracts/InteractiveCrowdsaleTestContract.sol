pragma solidity ^0.4.18;

/****************
*
*  Test contract for tesing libraries on networks
*
*****************/

import "./InteractiveCrowdsaleLib.sol";

contract InteractiveCrowdsaleTestContract {
  using InteractiveCrowdsaleLib for InteractiveCrowdsaleLib.InteractiveCrowdsaleStorage;

  InteractiveCrowdsaleLib.InteractiveCrowdsaleStorage sale;

  event LogErrorMsg(uint256 amount, string Msg);

  function InteractiveCrowdsaleTestContract(
    address owner,
    uint256 priceBonusPercent,
    uint256 minimumRaise,
    uint256 tokensPerEth,
    uint256 startTime,
    uint256 endWithdrawalTime,
    uint256 endTime,
    uint8 percentBeingSold,
    string tokenName,
    string tokenSymbol,
    uint8 tokenDecimals) public
  {
  	sale.init(owner,
              priceBonusPercent,
              minimumRaise,
              tokensPerEth,
              startTime,
              endWithdrawalTime,
              endTime,
              percentBeingSold,
              tokenName,
              tokenSymbol,
              tokenDecimals);
  }

  function () public {
    LogErrorMsg(0, 'Did not send correct data!');
  }

  function submitBid(uint256 _personalValuation, uint256 _listPredict) payable public returns (bool) {
    return sale.submitBid(msg.value, _personalValuation, _listPredict);
  }

  function withdrawBid() public returns (bool) {
    return sale.withdrawBid();
  }

  function withdrawLeftoverWei() public returns (bool) {
    return sale.withdrawLeftoverWei();
  }

  function retrieveFinalResult() public returns (bool) {
    return sale.retrieveFinalResult();
  }

  function finalizeSale() public returns (bool) {
    return sale.finalizeSale();
  }

  function withdrawOwnerEth() public returns (bool) {
  	return sale.withdrawOwnerEth();
  }

  function crowdsaleIsActive() public view returns (bool) {
  	return sale.crowdsaleIsActive();
  }

  function isFinalized() public view returns (bool) {
  	return sale.isFinalized;
  }

  function getOwner() public view returns (address) {
    return sale.owner;
  }

  function getTokensPerEth() public view returns (uint256) {
    return sale.tokensPerEth;
  }

  function getStartTime() public view returns (uint256) {
    return sale.startTime;
  }

  function getEndTime() public view returns (uint256) {
    return sale.endTime;
  }

  function getMinimumRaise() public view returns (uint256) {
    return sale.minimumRaise;
  }

  function getEndWithdrawlTime() public view returns (uint256) {
    return sale.endWithdrawalTime;
  }

  function getCommittedCapital() public view returns (uint256) {
    return sale.valueCommitted;
  }

  function getContribution(address _buyer) public view returns (uint256) {
    return sale.hasContributed[_buyer];
  }

  function getLeftoverWei(address _buyer) public view returns (uint256) {
    return sale.leftoverWei[_buyer];
  }

  function getPersonalCap(address _bidder) public view returns (uint256) {
    return sale.getPersonalCap(_bidder);
  }

  function getPrice(address _bidder) public view returns (uint256) {
    return sale.pricePurchasedAt[_bidder];
  }

  function getPercentBeingSold() public view returns (uint256) {
    return sale.percentBeingSold;
  }

  function getCurrentBucket() public view returns (uint256) {
    return sale.currentBucket;
  }

  function getTotalValuation() public view returns (uint256) {
    return sale.totalValuation;
  }

  function getTokenAddress() public view returns (address) {
    return address(sale.token);
  }

  function getValueCommitement(uint256 bucket) public view returns (uint256) {
    return sale.valuationSums[bucket];
  }

  function getOwnerBalance() public view returns (uint256) {
    /* Q: CrowdsaleStorage.ownerBalance is not public
      does this work?
      A: Yes, but it doesn't use the lib on-chain. The bytecode is actually included in this contract.
     */
    return sale.ownerBalance;
  }
}
