// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Ownable {
    address public owner;

    /**
      * dev The Ownable constructor sets the original `owner` of the contract to the sender
      * account.
      */
      constructor() {
        owner = msg.sender;
      }

    /**
      * dev Throws if called by any account other than the owner.
      */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
    * dev Allows the current owner to transfer control of the contract to a newOwner.
    * param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        if (newOwner != address(0)) {
            owner = newOwner;
        }
    }

}

contract TortoiseCoin is ERC20, Ownable {

    enum GameStatus {
        ACTIVE,
        LOCKED,
        DIE
    }

    enum GameType {
        NONE,
        SYSTEM,
        CUSTOM
    }

    struct PrizeResult {
        uint256 gameId;
        address ad;
        bool win;
        uint256 winAmount;
        uint256 amount;
        GameType gameType;
        uint point;
    }

    struct BetRecord {
        address ad;
        uint choice;
        uint256 money;
        uint256 gameId;
        bool prize;
    }

    struct Game {
        uint256 id;
        string name;
        string cover;
        GameType gameType;
        address owner;
        uint256 duration;
        GameStatus status;
    }

    struct SwapRecord {
        address owner;
        uint256 coinAmount;
        uint256 amount;
    }

    modifier checkBasicGame(string memory name, string memory cover, uint256 duration) {
        require(bytes(name).length > 1, "Game name charactor less 2");
        require(bytes(cover).length < 120, "Game name charactor great 120");
        require(duration >= 1800, "Game duration less than 1800 seconds");
        _;
    } 

    event Prize(PrizeResult);
    event Betting(BetRecord);
    event CreateGame(Game);
    event Swap(SwapRecord);
    event Log(string);
    event Log(uint256);

    uint256 maxSupply;
    uint256 MinPledge = 1e19; // min pledge coin value

    mapping(uint256 => BetRecord[]) bets; //game id => bet record
    mapping(uint256 => mapping(address => bool)) gamePlayers; // game id => ( player => status)
    mapping(address => uint256) pledges; // player => pledge amount
    mapping(address => uint256[]) ownerGames;  // player => owner game ids
    mapping(uint256 => uint256) betAmount;  // game id => total bet amount
    mapping(uint256 => Game) games; // game id => game detail
    uint256 public totalProfitAmount;

    uint256 public serviceRate = 5; // 0-100
    uint256 public distributeRate = 20; // 0-100
    uint256[] systemGames;
    uint256 gameNumber = 1;
    uint256[] customGames;
    uint256 nonce = 1;

    constructor(string memory name_, string memory symbol_, uint256 maxSupply_) ERC20(name_, symbol_) payable {
        maxSupply = maxSupply_;
    }
    receive() external payable {}
    fallback() external payable {}

    function decimals() public pure override returns (uint8) {
        return 0;
    }

    function _mint(address account, uint256 amount) internal override {
        if(amount < 1 || totalSupply() == maxSupply) {
            return;
        }

        if(maxSupply < totalSupply() + amount) {
            amount = maxSupply - totalSupply();
        }
        emit Log("mint amount");
        emit Log(amount);
        ERC20._mint(account, amount);
    }

    function createCustomGame(string memory name, string memory cover, uint256 duration) public  checkBasicGame(name, cover, duration) returns(bool) {
        require(pledges[msg.sender] > 0, "You need pledge some matic");

        uint256 nu = gameNumber;
        gameNumber++;

        ownerGames[msg.sender].push(nu);

        Game memory game = Game({
            name: name,
            id: nu,
            cover: cover,
            duration: duration + block.timestamp,
            gameType: GameType.CUSTOM,
            owner: msg.sender,
            status: GameStatus.ACTIVE
        });

        games[nu] = game;
        customGames.push(nu);

        emit CreateGame(game);

        return true;
    }

    function createSystemGame(string memory name, string memory cover, uint256 duration) public onlyOwner checkBasicGame(name, cover, duration) returns(bool) {

        uint256 nu = gameNumber;
        gameNumber++;

        Game memory game = Game({
            name: name,
            id: nu,
            cover: cover,
            duration: duration + block.timestamp,
            gameType: GameType.SYSTEM,
            owner: msg.sender,
            status: GameStatus.ACTIVE
        });

        games[nu] = game;
        systemGames.push(nu);

        emit CreateGame(game);

        return true;
    }

    function checkAllGames() public {
        uint256 len = systemGames.length;
        for(uint256 i = 1; i <= len; i++) {
            checkOneSystemGame(games[i]);
        }

        len = customGames.length;
        for(uint256 i = 1; i <= len; i++) {
            checkOneCustomGame(games[i]);
        }
    }

    function checkOneCustomGame(Game storage game) internal {
        if(game.duration > block.timestamp || game.status != GameStatus.ACTIVE) {
            return;
        }
       
        // require(game.duration <= block.timestamp, "The opening time has not arrived");
        // require(game.status == GameStatus.ACTIVE, "Game is not running");

        game.status = GameStatus.LOCKED;

        uint256 maxRandom = 10;
        uint256 bankerPoint = rand(maxRandom);
        address bankderAd = game.owner;

        emit Log("banker point");
        emit Log(bankerPoint);

        uint256 len = bets[game.id].length;
        uint256 serviceFeeAmount = 0;
        emit CreateGame(game);
        emit Log(len);
        emit Log(game.id);

        for(uint256 i = 0; i < len; i++) {
            BetRecord storage r = bets[game.id][i];
            emit Log("User point");
            r.choice = rand(maxRandom);
            r.prize = true;
            emit Log(r.choice);

            PrizeResult memory prizeRes = PrizeResult({
                gameId: game.id,
                amount: r.money,
                win: false,
                winAmount: r.money,
                ad: r.ad,
                gameType: GameType.SYSTEM,
                point: r.choice
            });

            if(r.choice > bankerPoint) {
                prizeRes.win = true;
                pledges[bankderAd] -= r.money;
                serviceFeeAmount += r.money * serviceRate / 100;
                (bool res,) = payable(r.ad).call{value: 2 * r.money  - r.money * serviceRate / 100}("");
                require(res, "Failed to cash the prize");
            }else {
                pledges[bankderAd] += r.money;
            }

            emit Prize(prizeRes);
        }

        ownerCommission(serviceFeeAmount);

        game.status = GameStatus.DIE;
    }

    function ownerCommission(uint256 serviceFeeAmount) internal {
         uint256 ownerFeeAmount = serviceFeeAmount * distributeRate / 100;
        totalProfitAmount += serviceFeeAmount - ownerFeeAmount;
        (bool feeRes,) = payable(owner).call{value: ownerFeeAmount}("");
        require(feeRes, "Service charge deduction failed");
    }

    function checkOneSystemGame(Game storage game) internal {
        if(game.duration > block.timestamp || game.status != GameStatus.ACTIVE) {
            return;
        }

        game.status = GameStatus.LOCKED;

        uint256 randNum = rand(2);
        emit Log("random num: ");
        emit Log(randNum);
        emit Log("random ok!");
        (uint256 w, uint256 l) = calculatePrize(game, randNum);
        emit Log(w);
        emit Log(l);
        emit Log("win lose value.");
        l = calculateCommission(l);
        emit Log(l);
        checkAllUserPrize(game, randNum, w, l);
    }

    function calculatePrize(Game storage game, uint256 randNum) internal view returns (uint256, uint256) {
        uint256 len = bets[game.id].length;
        uint256 winMoney = 0;
        uint256 loseMoney = 0;

        for(uint256 i = 0; i < len; i++) {
            BetRecord storage r = bets[game.id][i];
            if(r.choice == randNum) { //hit
                winMoney += r.money;
            }else {
                loseMoney += r.money;
            }
        }

        return (winMoney, loseMoney);
    }

    function calculateCommission(uint256 loseMoney) internal returns(uint256) {
        if(loseMoney == 0) {
            return loseMoney;
        }

        uint256 serviceFeeAmount = loseMoney * serviceRate / 100;

        ownerCommission(serviceFeeAmount);

        return loseMoney - serviceFeeAmount;
    }
 
    function checkAllUserPrize(Game storage game, uint256 randNum, uint256 w, uint256 l) internal {
        uint256 len = bets[game.id].length;
        for(uint256 i = 0; i < len; i++) {
            BetRecord storage r = bets[game.id][i];
            if(r.prize) {
                continue;
            }

            r.prize = true;

            PrizeResult memory prizeRes = PrizeResult({
                gameId: game.id,
                amount: r.money,
                win: false,
                winAmount: r.money,
                ad: r.ad,
                gameType: GameType.CUSTOM,
                point: r.choice
            });

            if(r.choice == randNum) { //hit
                uint256 winAmount = r.money * l / w;
                uint256 p2 = r.money + winAmount;
                prizeRes.winAmount = winAmount;
                prizeRes.win = true;
                (bool res,) = payable(r.ad).call{value: p2}("");
                require(res, "Failed to cash the prize");
            }

             emit Prize(prizeRes);
        }

        game.status = GameStatus.DIE;
    }

    function betting(uint256 id, uint256 c) public payable {
        require(games[id].id > 0, "Game not exist");
        require(games[id].status == GameStatus.ACTIVE, "Game invalid");
        require(games[id].duration > block.timestamp, "The game is over");
        require(msg.value >= 1e17, "Bet amount must greate than 0.1 Matic");
        require(!gamePlayers[id][msg.sender], "The same account can only participate once");

        address gameOwner = games[id].owner;
        require(gameOwner != msg.sender, "Can't bet yourself");
        if(games[id].gameType != GameType.SYSTEM) {
           require(pledges[gameOwner] > betAmount[id] + msg.value, "All bet amount is greater than pledge amount");
        }
        
        betAmount[id] += msg.value;
        BetRecord memory r = BetRecord({
            ad: msg.sender,
            choice: c,
            money: msg.value,
            gameId: id,
            prize: false
        });

        bets[id].push(r);
        gamePlayers[id][msg.sender] = true;
        (bool res,) = payable(this).call{value: msg.value}("");
        require(res, "Bet failed");

        _mint(msg.sender, msg.value * getPledgeRewardRate() / 1e18 / 10);

        emit Betting(r);
    }

    function rand(uint max) internal returns(uint256) {
        nonce++;
        uint256 random = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, nonce)));
        random = uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, nonce, random)));
        return random%max;
    }

    function setServiceRate(uint256 v) public onlyOwner {
        require(v < 10, "Exceeding the maximum serviceRate");
        serviceRate = v;
    }

    function getPledgeRewardRate() public view returns(uint256) {
        uint256 res = totalSupply() * 100 / maxSupply;
        uint256 r = (100 - res) ** 3 / 3000;

        return r < 1 ? 1 : r;
    }

    function pledge() public payable {
        require(msg.value >= MinPledge, "Less than the minimum pledge amount");
        if(pledges[msg.sender] > 0) {
            pledges[msg.sender] = pledges[msg.sender] + msg.value;
        }else {
            pledges[msg.sender] = msg.value;
        }
        (bool res,) = payable(this).call{value: msg.value}("");
        require(res, "Pledge failed");

        _mint(msg.sender, msg.value * getPledgeRewardRate() / 1e18);
    }

    function redeem() public payable {
        require(pledges[msg.sender] > 0, "No pledge can be redeemed");

        uint256 len = ownerGames[msg.sender].length;
        for(uint256 i = 0; i < len; i++) {
            require(games[ownerGames[msg.sender][i]].status == GameStatus.DIE, "There is a game not finished yet");
        }

        uint256 originVal = pledges[msg.sender];
        uint256 serviceFeeAmount = originVal * serviceRate / 100;
        uint256 redeemAmount = originVal - serviceFeeAmount;
        ownerCommission(serviceFeeAmount);
        
        pledges[msg.sender] = 0;
        (bool res,) = payable(msg.sender).call{value: redeemAmount}("");
        require(res, "Pledge redeem failed");

    }

    function swap(uint256 amount) public {
        require(amount > 0, "Swap less must great than 0");
        super._burn(msg.sender, amount);
        uint256 realAmount = amount - amount * getPledgeRewardRate()* serviceRate / 10000;
        uint256 value = totalProfitAmount * realAmount / totalSupply();
        totalProfitAmount -= value;
        (bool res,) = payable(msg.sender).call{value: value}("");
        require(res, "Swap failed");

        emit Swap(SwapRecord({
            owner: msg.sender,
            coinAmount: amount,
            amount: value
        }));
    }

    function setMinPledge(uint256 v) public onlyOwner {
        MinPledge = v;
    }

    function getPledgeAmount(address ad) public view returns(uint256) {
        return pledges[ad];
    }

    function getGameBetRecords(uint256 id) public view returns(BetRecord[] memory) {
        return bets[id];
    }

    function getSystemTime() public view returns (uint256) {
        return block.timestamp;
    }

    function getBalance(address ad) view public returns(uint256) {
        return ad.balance;
    }

    function getSystemGames() public view returns(uint256[] memory) {
        return systemGames;
    }

    function getCustomGames() public view returns(uint256[] memory) {
        return customGames;
    }

    function getGame(uint256 id) public view returns(Game memory) {
        return games[id];
    }

    function getBetAmount(uint256 id) public view returns(uint256) {
        return betAmount[id];
    }

}