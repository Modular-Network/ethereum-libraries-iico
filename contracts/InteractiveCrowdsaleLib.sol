pragma solidity ^0.4.21;

/**
 * @title InteractiveCrowdsaleLib
 * @author Modular, Inc
 *
 * version 2.0.0
 * Copyright (c) 2017 Modular, Inc
 * The MIT License (MIT)
 *
 * The InteractiveCrowdsale Library provides functionality to create a crowdsale
 * based on the white paper initially proposed by Jason Teutsch and Vitalik
 * Buterin. See https://people.cs.uchicago.edu/~teutsch/papers/ico.pdf for
 * further information.
 *
 * This library was developed in a collaborative effort among many organizations
 * including TrueBit, Modular, and Consensys.
 * For further information: truebit.io, modular.network,
 * consensys.net
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "ethereum-libraries-token/contracts/TokenLib.sol";
import "ethereum-libraries-linked-list/contracts/LinkedListLib.sol";
import "./InteractiveCrowdsaleToken.sol";

library InteractiveCrowdsaleLib {
  using SafeMath for uint256;
  using TokenLib for TokenLib.TokenStorage;
  using LinkedListLib for LinkedListLib.LinkedList;

  // Node constants for use in the linked list
  uint256 constant NULL = 0;
  uint256 constant HEAD = 0;
  bool constant PREV = false;
  bool constant NEXT = true;

  struct InteractiveCrowdsaleStorage {

    address owner;     //owner of the crowdsale

  	uint256 tokensPerEth;  //number of tokens received per ether
  	uint256 startTime; //ICO start time, timestamp
  	uint256 endTime; //ICO end time, timestamp automatically calculated
    uint256 ownerBalance; //owner wei Balance
    uint256 startingTokenBalance; //initial amount of tokens for sale

    //shows how much wei an address has contributed
  	mapping (address => uint256) hasContributed;

    //For token withdraw function, maps a user address to the amount of tokens they can withdraw
  	mapping (address => uint256) withdrawTokensMap;

    // any leftover wei that buyers contributed that didn't add up to a whole token amount
    mapping (address => uint256) leftoverWei;

  	InteractiveCrowdsaleToken token; //token being sold

    // List of personal valuations, sorted from smallest to largest (from LinkedListLib)
    LinkedListLib.LinkedList valuationsList; /* OK, so this is the linkedlist of different peoples valuation caps.. */

    // Info holder for token creation
    TokenLib.TokenStorage tokenInfo; /* These are the values that will ultimately  */

    uint256 endWithdrawalTime;   // time when manual withdrawals are no longer allowed

    // current total valuation of the sale
    // actual amount of ETH committed, taking into account partial purchases
    uint256 totalValuation;

    // amount of value committed at this valuation, cannot rely on owner balance
    // due to fluctations in commitment calculations needed after owner withdraws
    // in other words, the total amount of ETH committed, including total bids
    // that will eventually get partial purchases
    uint256 valueCommitted;

    // the bucket that sits either at or just below current total valuation.
    // determines where the cutoff point is for bids in the sale
    uint256 currentBucket;

    // the fraction of each minimal valuation bidder's ether refund, 'q' is from the paper
    // and is calculated when finalizing the sale
    uint256 q;

    // minimim amount that the sale needs to make to be successfull
    uint256 minimumRaise;

    // percentage of total tokens being sold in this sale
    uint8 percentBeingSold;

    // the bonus amount for early bidders.  This is a percentage of the base token
    // price that gets added on the the base token price used in getCurrentBonus()
    uint256 priceBonusPercent;

    // Indicates that the owner has finalized the sale and withdrawn Ether
    bool isFinalized;

    // Set to true if the sale is canceled
    bool isCanceled;

    // shows the price that the address purchased tokens at
    mapping (address => uint256) pricePurchasedAt;

    // the sums of bids at each valuation.  Used to calculate the current bucket for the valuation pointer
    mapping (uint256 => uint256) valuationSums;

    // the number of active bids at a certain valuation cap
    mapping (uint256 => uint256) numBidsAtValuation;

    // the valuation cap that each address has submitted
    mapping (address => uint256) personalCaps;

    // shows if an address has done a manual withdrawal. manual withdrawals are only allowed once
    mapping (address => bool) hasManuallyWithdrawn;
  }

  // Indicates when an address has withdrawn their supply of tokens
  event LogTokensWithdrawn(address indexed _bidder, uint256 Amount);

  // Indicates when an address has withdrawn their supply of extra wei
  event LogWeiWithdrawn(address indexed _bidder, uint256 Amount);

  // Logs when owner has pulled eth
  event LogOwnerEthWithdrawn(address indexed owner, uint256 amount, string Msg);

  // Indicates when a bidder submits a bid to the crowdsale
  event LogBidAccepted(address indexed bidder, uint256 amount, uint256 personalValuation);

  // Indicates when a bidder manually withdraws their bid from the crowdsale
  event LogBidWithdrawn(address indexed bidder, uint256 amount, uint256 personalValuation);

  // Indicates when a bid is removed by the automated bid removal process
  event LogBidRemoved(address indexed bidder, uint256 personalValuation);

  // Generic Error Msg Event
  event LogErrorMsg(uint256 amount, string Msg);

  // Indicates when the price of the token changes
  event LogTokenPriceChange(uint256 amount, string Msg);

  // Logs the current bucket that the valuation points to, the total valuation of
  // the sale, and the amount of ETH committed, including total bids that will eventually get partial purchases
  event BucketAndValuationAndCommitted(uint256 bucket, uint256 valuation, uint256 committed);

  modifier saleEndedNotFinal(InteractiveCrowdsaleStorage storage self) {
    require(now > self.endTime && (!self.isFinalized));
    _;
  }

  /// @dev Called by a crowdsale contract upon creation.
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _owner Address of crowdsale owner
  /// @param _priceBonusPercent the bonus amount for early bidders
  /// @param _minimumRaise minimim amount that the sale needs to make to be successfull
  /// @param _tokensPerEth the number of tokens to be received per ether sent
  /// @param _startTime timestamp of sale start time
  /// @param _endWithdrawalTime timestamp that indicates that manual withdrawals are no longer allowed
  /// @param _endTime Timestamp of sale end time
  /// @param _percentBeingSold percentage of total tokens being sold in the sale
  /// @param _tokenName name of the token being sold. ex: "Jason Network Token"
  /// @param _tokenSymbol symbol of the token. ex: "JNT"
  /// @param _tokenDecimals number of decimals in the token
  /* NOTE: This is basically the code which will be called by the constructor of the calling contract
      Question: is there anything that can be done here to fuck with the Library contract itself?
        Does solidity Guarantee that a Library is stateless?
   */
  function init(InteractiveCrowdsaleStorage storage self,
                address _owner,
                uint256 _priceBonusPercent,
                uint256 _minimumRaise,
                uint256 _tokensPerEth,
                uint256 _startTime,
                uint256 _endWithdrawalTime,
                uint256 _endTime,
                uint8 _percentBeingSold,
                string _tokenName,
                string _tokenSymbol,
                uint8 _tokenDecimals) internal
  {
    //g base.startTime is start of ICO
    //g base.endTime is end of ICO
    //g times are checked endTime > endWithdrawalTime > startTime
    require(self.owner == 0);
    require(_owner > 0);
    require(_endWithdrawalTime < _endTime);
    require(_endWithdrawalTime > _startTime);
    require(_minimumRaise > 0);
    require(_percentBeingSold > 0);
    require(_percentBeingSold <= 100);
    require(_priceBonusPercent > 0);

    /* Just sets a bunch of parameters for the sale in the struct. This must be a massive struct in storage */
    self.owner = _owner;
    self.priceBonusPercent = _priceBonusPercent;
    self.minimumRaise = _minimumRaise;
    self.tokensPerEth = _tokensPerEth;
    self.startTime = _startTime;
    self.endWithdrawalTime = _endWithdrawalTime;
    self.endTime = _endTime;
    self.percentBeingSold = _percentBeingSold;
    self.tokenInfo.name = _tokenName;
    self.tokenInfo.symbol = _tokenSymbol;
    self.tokenInfo.decimals = _tokenDecimals;
  }

  /// @dev calculates the number of digits in a given number
  /// @param _number the number for which we're caluclating digits
  /// @return _digits the number of digits in _number
  /* J: I tested out this and it seemed to work for  */
  function numDigits(uint256 _number) private pure returns (uint256) {
    uint256 _digits = 0;
    while (_number != 0) {
      _number /= 10;
      _digits++;
    }
    return _digits;
  }

  /// @dev calculates the number of tokens purchased based on the amount of wei
  ///      spent and the price of tokens
  /// @param _amount amound of wei that the buyer sent
  /// @param _price price of tokens in the sale, in tokens/ETH
  /// @return uint256 numTokens the number of tokens purchased
  /// @return remainder  any remaining wei leftover from integer division
  function calculateTokenPurchase(uint256 _amount,
                                  uint256 _price)
                                  private
                                  pure
                                  returns (uint256,uint256)
  {
    uint256 remainder = 0; //temp calc holder for division remainder for leftover wei

    uint256 numTokens;
    uint256 weiTokens; //temp calc holder

    // Find the number of tokens as a function in wei
    weiTokens = _amount.mul(_price);

    numTokens = weiTokens / 1000000000000000000;
    remainder = weiTokens % 1000000000000000000;
    remainder = remainder / _price;

    return (numTokens,remainder);
  }

  /// @dev Called when an address wants to submit a bid to the sale
  /// @param self Stored crowdsale from crowdsale contract
  /// @return currentBonus percentage of the bonus that is applied for the purchase
  function getCurrentBonus(InteractiveCrowdsaleStorage storage self) private view returns (uint256){

    uint256 bonusTime;
    uint256 elapsed;
    uint256 currentBonus;

    bonusTime = self.endWithdrawalTime.sub(self.startTime);
    elapsed = now.sub(self.startTime);

    uint256 percentElapsed = (elapsed.mul(100))/bonusTime;

    currentBonus = self.priceBonusPercent.sub(((percentElapsed.mul(self.priceBonusPercent))/100));

    return currentBonus;
  }

  function isAValidPurchase(InteractiveCrowdsaleStorage storage self) private view returns (bool){
    require(msg.sender != self.owner); /* J: Interesting, so owner can't bid? OK. */

    bool nonZeroPurchase = msg.value != 0;
    require(nonZeroPurchase);
    // bidder can't have already bid   /* Hmmm... why not? Probably just makes logic easier. */ <--- To prevent false signaling
    require((self.personalCaps[msg.sender] == 0) && (self.hasContributed[msg.sender] == 0));
    return true;
  }

  /// @dev Called when an address wants to submit bid to the sale
  /// @param self Stored crowdsale from crowdsale contract
  /// @param _amount amound of wei that the buyer is sending
  /// @param _personalCap the total crowdsale valuation (wei) that the bidder is comfortable with
  /// @param _valuePredict prediction of where the valuation will go in the linked list. saves on searching time
  /// @return true on succesful bid
  function submitBid(InteractiveCrowdsaleStorage storage self,
                      uint256 _amount,
                      uint256 _personalCap,
                      uint256 _valuePredict)
                      public
                      returns (bool)
  {
    require(crowdsaleIsActive(self));
    require(isAValidPurchase(self));
    uint256 _bonusPercent;
    uint256 placeholder;
    // token purchase bonus only applies before the withdrawal lock
    if (isBeforeWithdrawalLock(self)) { /* first half of the sale */
      require(_personalCap > _amount); /* Kind of a silly check, but I guess it would be bad if this was false. */
      _bonusPercent = getCurrentBonus(self);
    } else { /* Thus we're in the second half of the sale. validPurchase ensures it's not over.*/
      // The personal valuation submitted must be greater than the current
      // valuation plus the bid if after the withdrawal lock.
      require(_personalCap >= self.totalValuation.add(_amount)); /* Your max cap must be at least the current total valuation, plus your contribution. */
    }

    // personal valuation and minimum should be set to the proper granularity,
    // only three most significant values can be non-zero. reduces the number of possible
    // valuation buckets in the linked list
    placeholder = numDigits(_personalCap);
    if(placeholder > 3) {
      /* Must be divisible by 10x the number of digits over 3.
        ie. 1230 has 4 digits. It's divisible by (4-3)*10 = 10, so it's OK.
       */
      require((_personalCap % (10**(placeholder - 3))) == 0); /* J: I checked this math, it's good. */
    }

    // add the bid to the sorted valuations list
    // duplicate personal valuation caps share a spot in the linked list
    /* J: LinkedListLib is going to need careful review */
    if(!self.valuationsList.nodeExists(_personalCap)){
        placeholder = self.valuationsList.getSortedSpot(_valuePredict,_personalCap,NEXT);
        self.valuationsList.insert(placeholder,_personalCap,PREV);
    }

    // add the bid to the address => cap mapping
    self.personalCaps[msg.sender] = _personalCap;

    // add the bid to the sum of bids at this valuation. Needed for calculating correct valuation pointer
    self.valuationSums[_personalCap] = self.valuationSums[_personalCap].add(_amount);

    self.numBidsAtValuation[_personalCap] = self.numBidsAtValuation[_personalCap].add(1);

    // add the bid to bidder's contribution amount
    /* Note: the above requires (self.hasContributed[msg.sender] == 0)
      But this comment seems to suggest otherwise.
    */
    self.hasContributed[msg.sender] = self.hasContributed[msg.sender].add(_amount);

    // temp variables for calculation
    uint256 _proposedCommit;
    uint256 _currentBucket;
    bool loop;
    bool exists;
    /* J: reviewed the function up to this point */
    // we only affect the pointer if we are coming in above it
    if(_personalCap > self.currentBucket){

      // if our valuation is sitting at the current bucket then we are using
      // commitments right at their cap
      if (self.totalValuation == self.currentBucket) {
        // we are going to drop those commitments to see if we are going to be
        // greater than the current bucket without them
        _proposedCommit = (self.valueCommitted.sub(self.valuationSums[self.currentBucket])).add(_amount);

        if(_proposedCommit > self.currentBucket){ loop = true; }
      } else {
        // else we're sitting in between buckets and have already dropped the
        // previous commitments
        _proposedCommit = self.totalValuation.add(_amount);
        loop = true;
      }

      if(loop){
        // if we're going to loop we move to the next bucket
        (exists,_currentBucket) = self.valuationsList.getAdjacent(self.currentBucket, NEXT);

        while(_proposedCommit >= _currentBucket){
          // while we are proposed higher than the next bucket we drop commitments
          // and iterate to the next
          _proposedCommit = _proposedCommit.sub(self.valuationSums[_currentBucket]);

          /**Stop checking err here**/
          (exists,_currentBucket) = self.valuationsList.getAdjacent(_currentBucket, NEXT);
        }
        // once we've reached a bucket too high we move back to the last bucket and set it
        (exists, _currentBucket) = self.valuationsList.getAdjacent(_currentBucket, PREV);
        self.currentBucket = _currentBucket;
      } else {
        // else we're staying at the current bucket
        _currentBucket = self.currentBucket;
      }
      // if our proposed commitment is less than or equal to the bucket
      if(_proposedCommit <= _currentBucket){
        // we add the commitments in that bucket
        _proposedCommit = self.valuationSums[_currentBucket].add(_proposedCommit);
        // and our value is capped at that bucket
        self.totalValuation = _currentBucket;
      } else {
        // else our total value is in between buckets and it equals the total commitements
        self.totalValuation = _proposedCommit;
      }

      self.valueCommitted = _proposedCommit;
    } else if(_personalCap == self.totalValuation){
      self.valueCommitted = self.valueCommitted.add(_amount);
    }

    self.pricePurchasedAt[msg.sender] = (self.tokensPerEth.mul(_bonusPercent.add(100)))/100;
    LogBidAccepted(msg.sender, _amount, _personalCap);
    BucketAndValuationAndCommitted(self.currentBucket, self.totalValuation, self.valueCommitted);
    return true;
  }


  /// @dev Called when an address wants to manually withdraw their bid from the
  ///      sale. puts their wei in the LeftoverWei mapping
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true on succesful
  function withdrawBid(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    // The sender has to have already bid on the sale
    require(self.personalCaps[msg.sender] > 0);
    require(crowdsaleIsActive(self));
    uint256 refundWei;
    // cannot withdraw after compulsory withdraw period is over unless the bid's
    // valuation is below the cutoff
    if (isAfterWithdrawalLock(self)) {
      require(self.personalCaps[msg.sender] < self.totalValuation);

      // full refund because their bid no longer affects the total sale valuation
      /* FLAG: queuing up a refund without checking self.hasManuallyWithdrawn? */
      refundWei = self.hasContributed[msg.sender];
    } else {
      require(!self.hasManuallyWithdrawn[msg.sender]);  // manual withdrawals are only allowed once
      /***********************************************************************
      The following lines were commented out due to stack depth, but they represent
      the variables and calculations from the paper. The actual code is the same
      thing spelled out using current variables.  See section 4 of the white paper for formula used
      ************************************************************************/
      //uint256 t = self.endWithdrawalTime - self.startTime;
      //uint256 s = now - self.startTime;
      //uint256 pa = self.pricePurchasedAt[msg.sender];
      //uint256 pu = self.tokensPerEth;
      //uint256 multiplierPercent =  (100*(t - s))/t;
      //self.pricePurchasedAt = pa-((pa-pu)/3)
      uint256 timeLeft;

      timeLeft = self.endWithdrawalTime.sub(now);
      uint256 multiplierPercent = (timeLeft.mul(100)) / (self.endWithdrawalTime.sub(self.startTime));

      refundWei = (multiplierPercent.mul(self.hasContributed[msg.sender])) / 100;
      self.valuationSums[self.personalCaps[msg.sender]] = self.valuationSums[self.personalCaps[msg.sender]].sub(refundWei);

      self.numBidsAtValuation[self.personalCaps[msg.sender]] = self.numBidsAtValuation[self.personalCaps[msg.sender]].sub(1);

      uint256 bonusAmount;
      bonusAmount = self.pricePurchasedAt[msg.sender].sub(self.tokensPerEth);
      self.pricePurchasedAt[msg.sender] = self.pricePurchasedAt[msg.sender].sub(bonusAmount / 3);

      self.hasManuallyWithdrawn[msg.sender] = true;

    }

    // Put the sender's contributed wei into the leftoverWei mapping for later withdrawal
    self.leftoverWei[msg.sender] = self.leftoverWei[msg.sender].add(refundWei);

    // subtract the bidder's refund from its total contribution
    self.hasContributed[msg.sender] = self.hasContributed[msg.sender].sub(refundWei);

    uint256 _proposedCommit;
    uint256 _proposedValue;
    uint256 _currentBucket;
    bool loop;
    bool exists;

    // bidder's withdrawal only affects the pointer if the personal cap is at or
    // above the current valuation
    if(self.personalCaps[msg.sender] >= self.totalValuation){

      // first we remove the refundWei from the committed value
      _proposedCommit = self.valueCommitted.sub(refundWei);

      // if we've dropped below the current bucket
      if(_proposedCommit <= self.currentBucket){
        // and current valuation is above the bucket
        if(self.totalValuation > self.currentBucket){
          _proposedCommit = self.valuationSums[self.currentBucket].add(_proposedCommit);
        }

        if(_proposedCommit >= self.currentBucket){
          _proposedValue = self.currentBucket;
        } else {
          // if we are still below the current bucket then we need to iterate
          loop = true;
        }
      } else {
        if(self.totalValuation == self.currentBucket){
          _proposedValue = self.totalValuation;
        } else {
          _proposedValue = _proposedCommit;
        }
      }

      if(loop){
        // if we're going to loop we move to the previous bucket
        (exists,_currentBucket) = self.valuationsList.getAdjacent(self.currentBucket, PREV);
        while(_proposedCommit <= _currentBucket){
          // while we are proposed lower than the previous bucket we add commitments
          _proposedCommit = self.valuationSums[_currentBucket].add(_proposedCommit);
          // and iterate to the previous
          if(_proposedCommit >= _currentBucket){
            _proposedValue = _currentBucket;
          } else {
            (exists,_currentBucket) = self.valuationsList.getAdjacent(_currentBucket, PREV);
          }
        }

        if(_proposedValue == 0) { _proposedValue = _proposedCommit; }

        self.currentBucket = _currentBucket;
      }

      self.totalValuation = _proposedValue;
      self.valueCommitted = _proposedCommit;
    }

    LogBidWithdrawn(msg.sender, refundWei, self.personalCaps[msg.sender]);
    BucketAndValuationAndCommitted(self.currentBucket, self.totalValuation, self.valueCommitted);
    return true;
  }

  /// @dev This should be called once the sale is over to commit all bids into
  ///      the owner's bucket.
  /// @param self stored crowdsale from crowdsale contract

  //g !!! Shouldn't this just be callable by the owner !!!
  function finalizeSale(InteractiveCrowdsaleStorage storage self) public
           saleEndedNotFinal(self)
           returns (bool)
  {
    setCanceled(self);

    self.isFinalized = true;
    require(launchToken(self));
    //g may need to be computed due to EVM rounding errors
    uint256 computedValue;

    //g if it has not been canceld then calculate the ownerBalance
    if(!self.isCanceled){
      if(self.totalValuation == self.currentBucket){
        // calculate the fraction of each minimal valuation bidders ether and tokens to refund
        self.q = ((((self.valueCommitted.sub(self.totalValuation)).mul(100)))/self.valuationSums[self.totalValuation]).add(uint256(1));
        computedValue = self.valueCommitted.sub(self.valuationSums[self.totalValuation]);
        computedValue = computedValue.add(((uint256(100).sub(self.q)).mul(self.valuationSums[self.totalValuation]))/100);
      } else {
        // no computation necessary
        computedValue = self.totalValuation;
      }
      self.ownerBalance = computedValue;  // sets ETH raised in the sale to be ready for withdrawal
    }
  }

  /// @dev Mints the token being sold by taking the percentage of the token supply
  ///      being sold in this sale along with the valuation, derives all necessary
  ///      values and then transfers owner tokens to the owner.
  /// @param self Stored crowdsale from crowdsale contract
  function launchToken(InteractiveCrowdsaleStorage storage self) private returns (bool) {
    // total valuation of all the tokens not including the bonus
    uint256 _fullValue = (self.totalValuation.mul(100))/uint256(self.percentBeingSold);
    // total valuation of bonus tokens
    uint256 _bonusValue = ((self.totalValuation.mul(self.priceBonusPercent.add(100)))/100).sub(self.totalValuation);
    // total supply of all tokens not including the bonus
    uint256 _supply = (_fullValue.mul(self.tokensPerEth))/1000000000000000000;
    // total number of bonus tokens
    uint256 _bonusTokens = (_bonusValue.mul(self.tokensPerEth))/1000000000000000000;
    // tokens allocated to the owner of the sale
    uint256 _ownerTokens = _supply.sub((_supply.mul(uint256(self.percentBeingSold)))/100);
    // total supply of tokens including the bonus tokens
    uint256 _totalSupply = _supply.add(_bonusTokens);

    // deploy new token contract with total number of tokens
    self.token = new InteractiveCrowdsaleToken(address(this),
                                               self.tokenInfo.name,
                                               self.tokenInfo.symbol,
                                               self.tokenInfo.decimals,
                                               _totalSupply);


    if(!self.isCanceled){
      //g only the owner tokens go to the owner
      self.token.transfer(self.owner, _ownerTokens);
    } else {
      //g if the sale got canceled, then all the tokens go to the owner and bonus tokens are burned
      self.token.transfer(self.owner, _supply);
      self.token.burnToken(_bonusTokens);
    }
    // the owner of the crowdsale becomes the new owner of the token contract
    self.token.changeOwner(self.owner);
    self.startingTokenBalance = _supply.sub(_ownerTokens);

    return true;
  }

  /// @dev returns a boolean indicating if the sale is canceled.
  ///      This can either be if the minimum raise hasn't been met
  ///      or if it is 30 days after the sale and the owner hasn't finalized the sale.
  /* That's a weird condition */
  /// @return bool canceled indicating if the sale is canceled or not
  function setCanceled(InteractiveCrowdsaleStorage storage self) private returns(bool){
    bool canceled = (self.totalValuation < self.minimumRaise) ||
                    ((now > (self.endTime + 30 days)) && !self.isFinalized);

    if(canceled) {self.isCanceled = true;}

    return self.isCanceled;
  }

  /// @dev If the address' personal cap is below the pointer, refund them all their ETH.
  ///      if it is above the pointer, calculate tokens purchased and refund leftoever ETH
  /// @param self Stored crowdsale from crowdsale contract
  /// @return bool success if the contract runs successfully
  /* What should not happen here? */
  function retrieveFinalResult(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    require(now > self.endTime); /* This ensure that the endTime is past */
    require(self.personalCaps[msg.sender] > 0); /* This requires that  */

    uint256 numTokens; /* setup some pointers */
    uint256 remainder;

    //g seriously ?
    //g  self.isCanceled is checked twice and setCanceled is always true

    if(!self.isFinalized){
      require(setCanceled(self));
    }

    if (self.isCanceled) {
      // if the sale was canceled, everyone gets a full refund
      self.leftoverWei[msg.sender] = self.leftoverWei[msg.sender].add(self.hasContributed[msg.sender]);
      self.hasContributed[msg.sender] = 0;
      LogErrorMsg(self.totalValuation, "Sale is canceled, all bids have been refunded!");
      return true;
    }

    if (self.personalCaps[msg.sender] < self.totalValuation) {

      // full refund if personal cap is less than total valuation
      self.leftoverWei[msg.sender] += self.hasContributed[msg.sender];

      // set hasContributed to 0 to prevent participant from calling this over and over
      self.hasContributed[msg.sender] = 0;

      return withdrawLeftoverWei(self);

    } else if (self.personalCaps[msg.sender] == self.totalValuation) {

      // calculate the portion that this address has to take out of their bid
      uint256 refundAmount = (self.q.mul(self.hasContributed[msg.sender]))/100;
      uint256 dust = (self.q.mul(self.hasContributed[msg.sender]))%100;

      // refund that amount of wei to the address
      self.leftoverWei[msg.sender] = self.leftoverWei[msg.sender].add(refundAmount);

      // subtract that amount the address' contribution
      self.hasContributed[msg.sender] = self.hasContributed[msg.sender].sub(refundAmount);
      if(dust > 0) {
        self.leftoverWei[msg.sender] = self.leftoverWei[msg.sender].add(dust);
        self.hasContributed[msg.sender] = self.hasContributed[msg.sender].sub(dust);
      }
    }

    // calculate the number of tokens that the bidder purchased
    (numTokens, remainder) = calculateTokenPurchase(self.hasContributed[msg.sender],
                                                    self.pricePurchasedAt[msg.sender]);

    self.withdrawTokensMap[msg.sender] = self.withdrawTokensMap[msg.sender].add(numTokens);
    self.valueCommitted = self.valueCommitted.sub(remainder);
    self.hasContributed[msg.sender] = self.hasContributed[msg.sender].sub(remainder);
    self.leftoverWei[msg.sender] = self.leftoverWei[msg.sender].add(remainder);

    // burn any extra bonus tokens
    uint256 _fullBonus;
    uint256 _fullBonusPrice = (self.tokensPerEth.mul(self.priceBonusPercent.add(100)))/100;
    (_fullBonus, remainder) = calculateTokenPurchase(self.hasContributed[msg.sender], _fullBonusPrice);
    uint256 _leftoverBonus = _fullBonus.sub(numTokens);

    self.token.burnToken(_leftoverBonus);

    self.hasContributed[msg.sender] = 0;

    // send tokens and leftoverWei to the address calling the function
    withdrawTokens(self);

    withdrawLeftoverWei(self);

  }

  /// @dev Function called by purchasers to pull tokens
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if tokens were withdrawn
  function withdrawTokens(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    bool ok;

    if (self.withdrawTokensMap[msg.sender] == 0) {
      LogErrorMsg(0, "Sender has no tokens to withdraw!");
      return false;
    }

    if (msg.sender == self.owner) {
      if(!self.isFinalized){
        LogErrorMsg(0, "Owner cannot withdraw extra tokens until after the sale!");
        return false;
      }
    }

    uint256 total = self.withdrawTokensMap[msg.sender];
    self.withdrawTokensMap[msg.sender] = 0;
    ok = self.token.transfer(msg.sender, total); /* MYTHRIL: ==== CALL with gas to dynamic address ==== */
    require(ok);
    LogTokensWithdrawn(msg.sender, total);
    return true;
  }

  /// @dev Function called by purchasers to pull leftover wei from their purchases
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if wei was withdrawn
  function withdrawLeftoverWei(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    if (self.leftoverWei[msg.sender] == 0) {
      LogErrorMsg(0, "Sender has no extra wei to withdraw!");
      return false;
    }

    uint256 total = self.leftoverWei[msg.sender];
    self.leftoverWei[msg.sender] = 0;
    msg.sender.transfer(total);
    LogWeiWithdrawn(msg.sender, total);
    return true;
  }

  /// @dev send ether from the completed crowdsale to the owners wallet address
  /// @param self Stored crowdsale from crowdsale contract
  /// @return true if owner withdrew eth
  /* FLAG: this function allows a withdrawal of the full ETH value. What if the participants still
    have ETH to withdraw? */
  function withdrawOwnerEth(InteractiveCrowdsaleStorage storage self) public returns (bool) {
    require(msg.sender == self.owner);
    require(self.ownerBalance > 0);
    require(self.isFinalized);

    uint256 amount = self.ownerBalance;
    self.ownerBalance = 0;
    self.owner.transfer(amount);
    LogOwnerEthWithdrawn(msg.sender,amount,"Crowdsale owner has withdrawn all funds!");

    return true;
  }

  function crowdsaleIsActive(InteractiveCrowdsaleStorage storage self) public view returns (bool) {
    return (now >= self.startTime && now <= self.endTime);
  }

  function isBeforeWithdrawalLock(InteractiveCrowdsaleStorage storage self) public view returns (bool) {
    return now < self.endWithdrawalTime;
  }

  function isAfterWithdrawalLock(InteractiveCrowdsaleStorage storage self) public view returns (bool) {
    return now >= self.endWithdrawalTime;
  }

  function getPersonalCap(InteractiveCrowdsaleStorage storage self, address _bidder) public view returns (uint256) {
    return self.personalCaps[_bidder];
  }

}
