pragma solidity ^0.4.18;

// 合约归属
contract Owned {
    address public owner;

    function Owned() public {
        owner = msg.sender;
    }
    // 一个函数执行的前置条件
    modifier onlyOwner() {
        require(msg.sender == owner);
        _; // modifier的固定结束写法
    }
    // 更改合约所有人，初始化的时候是小明
    function changeOwner(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}

// 标准ERC20Token
contract ERC20Token {
    /// total amount of tokens
    uint256 public totalSupply;
    function balanceOf(address _owner) constant returns (uint256 balance);
    function transfer(address _to, uint256 _value) returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);
    function approve(address _spender, uint256 _value) returns (bool success);
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

// 自己的token
contract XmbToken is Owned, ERC20Token {
    using SafeMath for uint256;
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public rechargeLimit = 30 ether; // 最高可一次购买 30 ether 的token 增加刷票成本、也可以用approve控制
    uint256 public rechargeRate = 1000; // 兑换以太坊 1:1000

    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256)) allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
	event MakePoem(string poem);
    event RechargeFaith(address indexed to, uint256 value, uint256 refund);

    function XmbToken(uint256 initialSupply, uint8 decimalUnits) public {
        name = "XmbToken";
        symbol = "XMB";
        balances[msg.sender] = initialSupply;
        decimals = decimalUnits;
    }
    
    // 增发方法
    function additional(uint256 _value) onlyOwner public returns (bool success) {
        if (balances[owner] + _value >= balances[owner]) {
            balances[owner] += _value;
            return true;
        }
        return false;
    }

    function transfer(address _to, uint256 _value) public returns (bool success) {
	    require(balances[msg.sender] >= _value && balances[_to] + _value >= balances[_to]);
	    
	    balances[msg.sender] -= _value;
	    balances[_to] += _value;
	    Transfer(msg.sender, _to, _value);
        return true;
	}

    function tansferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(msg.sender == owner);
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } 
        return false;
    } 

    function balanceOf(address _owner) constant public returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) public returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant public returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

    function rechargeFaith(uint256 rechargeAmount) internal {
        uint256 distrbution;
        uint256 _refund = 0;
        // 转入金额大于0 并且转换后小于可分发token的数量
        if ((rechargeAmount > 0) && (tokenExchange(rechargeAmount) < balances[owner])) {
            if (rechargeAmount > rechargeLimit) {
                // 超过兑换限制会把多余的退回去
                _refund = rechargeAmount.sub(rechargeLimit);
                msg.sender.transfer(_refund);
                distrbution = tokenExchange(rechargeLimit);
            } else {
                distrbution = tokenExchange(rechargeAmount);
            }
            balances[owner] -= distrbution;
            balances[msg.sender] += distrbution;
        }
        RechargeFaith(msg.sender, rechargeAmount, _refund);
    }

    function tokenExchange(uint256 inputAmount) internal returns (uint256) {
        return inputAmount.mul(rechargeRate);
    }

    function () public payable {
        require(msg.sender != 0x0 && msg.sender != owner);
        if (msg.value != 0) {
            rechargeFaith(msg.value);
        }
    }
}

// 游戏合约逻辑
contract Poetry is XmbToken {
    Poem[] public poems; // 所有诗歌
    uint256 public maxVotes; // 现有最高投票数
    uint[] public winners; // 现有最高票数的诗歌id 

    struct Poet {
        // 诗人的地址
        address poetAddr;   
        // 诗人的总票数
        uint256 voteSum;
    }

    event PoemAdded(address from, uint poemId);
    event PoemVoted(address from, address to, uint poemId, uint256 value);

    struct Poem {
        bytes32 poemHash;
        string content;
        uint256 votes;
        mapping (address => bool) voted;
        Poet poet;
    }

    modifier onlyMembers() {
        require(balances[msg.sender] > 0);
        _;
    }

    function newPoem(string poemContent) public returns (uint poemId) {
        poemId = poems.length++;

        Poem storage pm = poems[poemId];
        pm.content = poemContent;
        pm.votes = 0;
        pm.poet.poetAddr = msg.sender;

        PoemAdded(msg.sender, poemId);
    }

    function votePoem(uint poemId, uint256 _value) onlyMembers public {
        require(_value <= balances[msg.sender]);
        Poem storage pm = poems[poemId];
        require(!pm.voted[msg.sender]);
        pm.voted[msg.sender] = true;

        balances[msg.sender] -= _value;
        balances[pm.poet.poetAddr] += _value;
        pm.votes += _value;
        pm.poet.voteSum += _value;

        if (pm.votes > maxVotes) {
            maxVotes = pm.votes;
            resetWinner(poemId);
        } else if (pm.votes == maxVotes) {
            winners.push(poemId);
        }
        
        PoemVoted(msg.sender, pm.poet.poetAddr, poemId, _value);
    }

    // 奖励赢家 unfinished
    function reward() payable public returns (bool) {
        require(msg.sender == owner);
        
        for (uint i = 0; i <= winners.length-1; i++) {
            Poem[winners[i]].poet.poetAddr; 

        }
    }

    // 刷下现有最高分
    function resetWinner(uint poemId) internal {
        if (winners.length > 0) {
            for (uint i = 0; i < winners.length-1; i++) {
                delete winners[i];
            }
        }
        winners.push(poemId);
    }

}

// 安全计算方法库
library SafeMath {
  function mul(uint a, uint b) internal returns (uint) {
    uint c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint a, uint b) internal returns (uint) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint a, uint b) internal returns (uint) {
    assert(b <= a);
    return a - b;
  }

  function add(uint a, uint b) internal returns (uint) {
    uint c = a + b;
    assert(c >= a);
    return c;
  }

  function max64(uint64 a, uint64 b) internal constant returns (uint64) {
    return a >= b ? a : b;
  }

  function min64(uint64 a, uint64 b) internal constant returns (uint64) {
    return a < b ? a : b;
  }

  function max256(uint256 a, uint256 b) internal constant returns (uint256) {
    return a >= b ? a : b;
  }

  function min256(uint256 a, uint256 b) internal constant returns (uint256) {
    return a < b ? a : b;
  }
}
