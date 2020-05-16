pragma solidity ^0.5.0;

library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "mul overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "div zero");
        uint256 c = a / b;
        return c;
    }


    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "lower sub bigger");
        uint256 c = a - b;
        return c;
    }

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "overflow");

        return c;
    }

}

contract Ownable {

    address internal _owner;
    address internal _newOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event OwnershipAccepted(address indexed previousOwner, address indexed newOwner);

    constructor () internal {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }


    function owner() public view returns (address currentOwner, address newOwner) {
        currentOwner = _owner;
        newOwner = _newOwner;
    }

    modifier onlyOwner() {
        require(isOwner(msg.sender), "Ownable: caller is not the owner");
        _;
    }

    function isOwner(address account) public view returns (bool) {
        return account == _owner;
    }

    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");

        emit OwnershipTransferred(_owner, newOwner);
        _newOwner = newOwner;
    }

    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    function acceptOwnership() public {
        require(msg.sender == _newOwner, "Ownable: caller is not the new owner address");
        require(msg.sender != address(0), "Ownable: caller is the zero address");

        emit OwnershipAccepted(_owner, msg.sender);
        _owner = msg.sender;
        _newOwner = address(0);
    }
}

library Roles {

    struct Role {
        mapping(address => bool) bearer;
    }

    function add(Role storage role, address account) internal {
        require(!has(role, account), "Roles: account already has role");
        role.bearer[account] = true;
    }

    function remove(Role storage role, address account) internal {
        require(has(role, account), "Roles: account does not have role");
        role.bearer[account] = false;
    }

    function has(Role storage role, address account) internal view returns (bool) {
        require(account != address(0), "Roles: account is the zero address");
        return role.bearer[account];
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address who) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);

    function allowance(address owner, address spender) external view returns (uint256);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract FiltFund is Ownable {

    using SafeMath for *;
    using Roles for Roles.Role;

    address  private sqAddr = address(0x611d1BC971dfE642Ee5d4DA22924B0d2A2391d88);
    address  private devAddr = address(0x3BbC6F6710aCa900a5cA8a3504d4Ba6797B5942c);
    address  private stationAddr = address(0x8038af3665c1cCA335532263F8f2dA0ffFF5d523);
    address  private filtBackAddr = address(0x341D0e989587fc7fBa4fF2eb7F412AbFa07ac069);
    IERC20 _IFILT = IERC20(0xe78A0F7E598Cc8b0Bb87894B0F60dD2a88d6a8Ab);
    Roles.Role private _proxies;
    Roles.Role private _signors;

    struct User {
        uint id;
        address uAddr;
        address pAddr;
        uint freezeAmt;
        uint freeAmt;
        uint invAmt;
        uint isHasT3;
        uint wthdSumAmt;
        uint wthdAmt;
        uint ztAmt;
        uint ztAllAmt;
        uint jdAmt;
        uint rlsAllAmt;

        uint lineAmt;

        uint[] ordArr;

        uint regTime;
        uint status;
    }

    struct Order{
        uint id;
        uint invAmt;
        uint leftDay;
        uint invTime;
        uint status;
    }

    struct Product{
        uint id;
        uint invDay;
        uint price;
        uint min;
        uint rate;
        uint status;
    }

    mapping (address => mapping (uint => address[])) private exfilt_multi_addr;//多签

    uint private _startTime = 1584969021;
    uint private _uid = 0;
    uint private _oid = 0;
    uint private _pid = 0;
    uint private _rInvestCount;
    bool public _enabelTsf = false;

    uint private _fenhongPool = 0;
    uint private _baobenPool = 0;

    uint public _dayStationAmt = 0;
    uint public _dayDevAmt = 0;
    uint public _daySqAmt = 0;

    uint private _ONE_DAY = 86400;

    uint private _filtPool = 50000000 ether;
    uint public _filtOutAmt = 0;

    uint public _mpInAmt = 0;

    mapping(address => User) private _userMapping;
    mapping(uint => address) private _indexMapping;
    mapping(uint => Product) public _prdMapping;
    mapping(uint => Order) private _ordMapping;

    event SignorAdded(address indexed account);
    event SignorTsf(address from,address to);
    event BuyLog(address indexed user, uint pid, uint amt);
    event TsfLog(address indexed from,address indexed to, uint amt);
    event WtdLog(address indexed user,uint amt);
    event ExpFilt(address indexed addr,uint amt);
    event MultiSig(address indexed signor,address indexed to,uint amt);
    event TsfFilt(address indexed to,uint amt);
    event SyncWtd(address indexed user,uint amt);
    event RlsOrder(address indexed user,uint oid,uint amt);

    modifier onlyProxy() {
        require(isProxy(msg.sender), "caller does not have the Proxy role");
        _;
    }

    modifier onlySignor() {
        require(isSignor(msg.sender), "caller does not have the Signor role");
        _;
    }

    function isProxy(address account) public view returns (bool) {
        return _proxies.has(account);
    }

    function isSignor(address account) public view returns (bool) {
        return _signors.has(account);
    }

    function addSignor(address[] memory accounts) public onlyOwner {
        require(accounts.length ==6, "need 6");
        require(isSignor(msg.sender), "should be signors");
        for (uint i=0; i<accounts.length; i++){
            _signors.add(accounts[i]);
            emit SignorAdded(accounts[i]);
        }
    }

    function moveSignor(address toAddr) public onlySignor {
        _signors.remove(msg.sender);
        _signors.add(toAddr);
        emit SignorTsf(msg.sender,toAddr);
    }

    modifier onlyHuman {
        address addr = msg.sender;
        uint codeLength;
        assembly {codeLength := extcodesize(addr)}
        require(codeLength == 0, "sorry humans only");
        require(tx.origin == msg.sender, "sorry, humans only");
        _;
    }

    constructor () public {
        addProxy(msg.sender);
        _signors.add(msg.sender);
        _startTime = now;
    }

    function buy(address pAddr,uint pid,uint num) public onlyHuman {
        if (!isReged(msg.sender)) {
            regUser(msg.sender, pAddr);
            _buy(msg.sender, pid,num,1,true);
        }else{
            _buy(msg.sender, pid,num,1,false);
        }
    }

    function regsub(address subAddr, uint pid,uint num) public onlyHuman {
        require(subAddr != msg.sender, "subAddr can't be self");
        require(isNotBan(msg.sender), "is ban");
        require(!isReged(subAddr), "addr is exist");
        regUser(subAddr, msg.sender);
        _buy(subAddr,pid,num,2,true);
    }

    function rebuy(uint pid,uint num) public onlyHuman {
        require(isNotBan(msg.sender), "is ban");
        _buy(msg.sender, pid,num,3,false);
    }

    function _buy(address addr,uint pid,uint num,uint way,bool isnew) private {
        Product memory prod = _prdMapping[pid];
        require(prod.id !=0, "invalid prod");
        require(prod.status !=0, "invalid prod");
        require(num >= prod.min, "num error");

        User storage user = _userMapping[addr];
        require(user.id != 0, "need reg fst");
        uint invAmt = prod.price.mul(num);
        uint allAmt = invAmt.mul(105).div(100);
        _mpInAmt += allAmt.sub(invAmt);

        if(way ==1){
            require(_IFILT.balanceOf(msg.sender) >= allAmt, "less filt");
            require(_IFILT.allowance(msg.sender, address(this)) >= allAmt, "less mp");
            _IFILT.transferFrom(msg.sender, address(this), allAmt);

        }else if(way==2){
            User storage fromUser = _userMapping[msg.sender];
            require(allAmt <= fromUser.freeAmt, "freeAmt less");
            fromUser.freeAmt = fromUser.freeAmt.sub(allAmt);
        }else if(way==3){
            require(allAmt <= user.freeAmt, "freeAmt less");
            user.freeAmt = user.freeAmt.sub(allAmt);
        }

        if (_baobenPool < 50000 ether) {
            _baobenPool += invAmt.div(50);
        } else {
            _fenhongPool += invAmt.div(50);
        }

        _fenhongPool += invAmt.mul(44).div(100);

        _rInvestCount += 1;

        _dayStationAmt += invAmt.div(5);
        _dayDevAmt += invAmt.div(50);
        _daySqAmt += invAmt.div(50).add(invAmt.div(100));

        if(invAmt >=300 ether&&prod.invDay>=360&&user.invAmt==0){
            user.isHasT3 = 1;
        }
        user.invAmt += invAmt;
        user.freezeAmt += invAmt.mul(100+prod.rate).div(100);

        _oid++;
        Order storage order = _ordMapping[_oid];
        order.id = _oid;
        order.invAmt = invAmt;
        order.leftDay = prod.invDay;

        _ordMapping[_oid] = order;

        user.ordArr.push(_oid);

        emit BuyLog(user.uAddr,pid,invAmt);

        if (uint(user.pAddr) != 0) {
            jiliTeams(user.pAddr,  invAmt, 1, isnew);
        }
    }

    function rgtRwd(uint origAmt,uint left) private pure returns (uint){
        if(left <= 100 ether){
            origAmt = origAmt.div(60).mul(100);
        }else if(left > 100 ether && left <= 300 ether){
            origAmt = origAmt.div(80).mul(100);
        }else if(left > 300 ether){
            origAmt = origAmt;
        }

        return origAmt;
    }

    function jiliTeams(address pAddr,  uint invAmt,uint deep,bool isnew) private {
        address tmpReferrer = pAddr;
        if (deep > 12) {
            return;
        }

        User storage user = _userMapping[tmpReferrer];
        if (user.id == 0) {
            return;
        }

        if(deep==1){
            user.ztAmt += invAmt.mul(8).div(100);
            user.ztAllAmt += invAmt.mul(8).div(100);
            if(isnew){
                user.subCnt++;
            }
        }

        if (deep>1 &&deep <= 3) {

            user.jdAmt += rgtRwd(invAmt.div(50),user.freeAmt+user.freezeAmt);

        }else if (user.ztAllAmt >= 500 ether &&deep>3 && deep <= 7) {

            user.jdAmt += rgtRwd(invAmt.div(50),user.freeAmt+user.freezeAmt);

        }else if (user.ztAllAmt >= 800 ether && deep>7 && deep <= 9) {

            user.jdAmt += rgtRwd(invAmt.div(100),user.freeAmt+user.freezeAmt);

        }else if (user.ztAllAmt >= 800 ether && user.isHasT3==1 && deep>9 && deep <= 12) {

            user.jdAmt += rgtRwd(invAmt.div(100),user.freeAmt+user.freezeAmt);

        }
        user.lineAmt += invAmt;
        deep++;
        jiliTeams(user.pAddr,  invAmt,deep,isnew);
    }


    function tsf(address toAddr, uint amt) public onlyHuman {
        require(isReged(toAddr), "addr not exist");
        User storage fromUser = _userMapping[msg.sender];
        require(fromUser.id != 0, "pls reg fst");
        require(fromUser.status != 0, "is ban");
        require(amt > 0 && amt <= fromUser.freeAmt, "amt error");

        User storage toUser = _userMapping[toAddr];
        require(toUser.id != 0, "toUser not reg");
        require(toUser.status != 0, "toUser is ban");
        toUser.freeAmt += amt;
        fromUser.freeAmt -= amt;

        emit TsfLog(msg.sender,toAddr,amt);
    }

    function tixian(uint amt) public onlyHuman {
        User storage user = _userMapping[msg.sender];
        require(user.id != 0, "pls reg fst");
        require(user.status != 0, "is ban");
        require(_enabelTsf, "disable");
        require(amt > 0 && amt <= user.freeAmt, "amt error");

        if (amt > 0) {
            user.wthdSumAmt += amt;
            user.wthdAmt += amt.sub(amt / 10);
            if (amt < user.freeAmt) {
                user.freeAmt -= amt;
            } else {
                user.freeAmt = 0;
            }

            _filtOutAmt+=amt;

            emit WtdLog(msg.sender,amt);
        } else {
            revert("fail");
        }
    }

    function jiesuan() public onlyHuman {
        User storage user = _userMapping[msg.sender];
        require(user.id != 0, "pls reg fst");
        require(user.status != 0, "is ban");

        if (user.ztAmt > 0) {
            user.freeAmt += user.ztAmt;
            user.ztAmt = 0;
        }

        if (user.jdAmt > 0) {
            user.freeAmt += user.jdAmt;
            user.jdAmt = 0;
        }
    }

    function rlsOrder(uint oid) public onlyHuman {
        User storage user = _userMapping[msg.sender];
        require(user.id != 0, "pls reg fst");
        require(user.status != 0, "is ban");

        Order storage order = _ordMapping[oid];
        require(order.id != 0, "order not exist");
        require(order.status != 0, "order is close");
        require(order.leftDay > 0, "order is finish");
        require(order.uid == user.id, "not your order");

        Product memory prod = _prdMapping[order.pid];

        uint daySpan = now.sub(order.invTime).div(_ONE_DAY);
        if(daySpan > prod.invDay){
            daySpan = prod.invDay;
        }
        daySpan = daySpan -(prod.invDay - order.leftDay);

        require( daySpan >0, "rls next day");

        if(daySpan>order.leftDay){
            daySpan = order.leftDay;
        }

        uint bonous = order.invAmt.mul(100+prod.rate).div(100).div(prod.invDay).mul(daySpan);
        user.rlsAllAmt += bonous;
        user.freeAmt += bonous;
        if (user.freezeAmt > bonous) {
            user.freezeAmt -= bonous;
        } else {
            user.freezeAmt = 0;
        }

        if (_fenhongPool > bonous) {
            _fenhongPool -= bonous;
        } else {
            _fenhongPool = 0;
        }

        order.leftDay = order.leftDay.sub(daySpan);
        if(order.leftDay==0){
            order.status = 0;
        }
        emit RlsOrder(user.uAddr,oid,bonous);
    }

    function sendMoneyToUser(address payable uAddr, uint money) private {
        if (money > 0) {
            uAddr.transfer(money);
        }
    }

    function isReged(address addr) public view returns (bool) {
        User memory user = _userMapping[addr];
        return user.id != 0;
    }

    function isNotBan(address addr) public view returns (bool) {
        User memory user = _userMapping[addr];
        return user.status != 0;
    }

    function regUser(address addr, address pAddr) private {
        User storage user = _userMapping[addr];
        _uid++;
        user.id = _uid;
        user.uAddr = addr;
        user.pAddr = pAddr;
        user.status = 1;

        user.isHasT3 = 0;
        user.invAmt = 0;
        user.freeAmt = 0;
        user.freezeAmt = 0;

        user.subCnt =0;

        user.regTime = now;

        _userMapping[addr] = user;
        _indexMapping[_uid] = addr;
    }

    function inArray(uint _self, uint[] storage _array) internal view returns (bool _ret) {
        for (uint i = 0; i < _array.length; ++i) {
            if (_self == _array[i]) {
                return true;
            }
        }
        return false;
    }

    function banU( address addr) external onlyProxy {
        User storage user = _userMapping[addr];
        require(user.id != 0, "user not exists");
        if(user.status==1){
            user.status = 0;
        }else{
            user.status = 1;
        }
    }

    function expEth() external onlyOwner {
        uint256 balance = address(this).balance;
        sendMoneyToUser(address(uint160(filtBackAddr)),balance);
    }

    function expFilt(address to, uint amount) external onlySignor {
        require(_IFILT.balanceOf(address(this)) >= amount, "amt not enough");
        address[] memory signed = exfilt_multi_addr[to][amount];
        for(uint i=0; i<signed.length;i++){
            if(address(msg.sender) == signed[i]){
                revert('already signed');
            }
        }
        exfilt_multi_addr[to][amount].push(address(msg.sender));
        emit MultiSig(msg.sender,to,amount);
        if(signed.length>=5){
            _IFILT.transfer(to, amount);
            delete exfilt_multi_addr[to][amount];
            emit TsfFilt(to,amount);
        }
    }

    function expBase() external onlyProxy {
        uint allAmt = _daySqAmt + _dayDevAmt + _dayStationAmt;
        require(_IFILT.balanceOf(address(this)) >= allAmt, "amt less");
        if (_daySqAmt > 0) {
            _IFILT.transfer(sqAddr, _daySqAmt);
            _daySqAmt = 0;
        }
        if (_dayDevAmt > 0) {
            _IFILT.transfer(devAddr, _dayDevAmt);
            _dayDevAmt = 0;
        }
        if (_dayStationAmt > 0) {
            _IFILT.transfer(stationAddr, _dayStationAmt);
            _dayStationAmt = 0;
        }
    }

    function syncWthd(uint[] calldata uids) external onlyProxy {
        for (uint256 i = 0; i < uids.length; i++) {
            User storage user = _userMapping[_indexMapping[uids[i]]];
            if (user.id != 0&&user.wthdAmt>0) {
                emit SyncWtd(user.uAddr,user.wthdAmt);
                user.wthdAmt = 0;
            }
        }
    }

    function apInfo() public onlyHuman view returns  (uint[4] memory info){
        info[0] =_IFILT.totalSupply();
        info[1] =_IFILT.balanceOf(address(this));
        info[2] =_IFILT.balanceOf(address(msg.sender));
        info[3] =_IFILT.allowance(address(msg.sender), address(this));
        return info;
    }
}