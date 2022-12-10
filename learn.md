1、常见函数与修饰符
这俩是给接收以太使用的，ERC20未在文档中提及。
receive、fallback
receive:如果合约没有这个函数的话，意味着不能接受转账以太币。
fallback：当给这个合约转账是，这个合约没有receive也没有fallback会异常、如果有fallback，没有receive会自动调用fallback进行返还以太币。

view、pure
view：可以用来查看链上数据，但是不会修改状态。如果合约调用了一个没有标记view或者pure的函数，那么这个函数不能被标记为view。有其他改变状态的情况也不行。
pure：连查看都没有

2、