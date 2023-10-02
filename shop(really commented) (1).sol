// SPDX-License-Identifier: MIT
pragma solidity <=0.8.21;

import "hardhat/console.sol";

contract BuyingInShop {

    modifier OnlyShops() {
        bool isShop = false;
        for(uint i = 0; i < shops.length; i++) {
            if (shops[i].wallet == msg.sender) {
                isShop = true;
            }
        } 
        require(isShop == true, "Only shop can do it!");
        _;
    }
    modifier OnlyClient() {
        for(uint i = 0; i < dnsSuppliers.length; i++) {
            require(dnsSuppliers[i].wallet != msg.sender, "Only client can do it!");
        }
        for(uint i = 0; i < shops.length; i++) {
            require(shops[i].wallet != msg.sender, "Only client can do it!");
        }
        _;
    }
    modifier OnlyExistingOrders(uint _purshareId) {
        require(_purshareId < purshares.length, "This purshare is don`t created yet!");
        _;
    }
    modifier OnlyOwner() {
        require(owner == msg.sender, "You aren`t an owner!");
        _;
    }
    modifier OnlyCreated(uint purshId) {
        require(purshares[purshId].status == Status.Created, "You confirmed/canceled this order early");
        _;
    }


    enum Role {
        Client,
        Supplier,
        Shop,
        Owner
    }
    enum Status {
        Created,
        Confirmed,
        Canceled,
        Finished,
        ReturnedNotPaid,
        ReturnedPaid
    }


    struct Querries {
        uint querryId;
        address requesterAddress;
        string name;
        Role role;
    }
    struct Client {
        address wallet;
        string nickName;
        bool isReferal;
    }
    struct Purshares {
        string trackNumber;
        uint clientId;
        uint shopId;
        uint prodId;
        uint count;
        uint daysFromSupply;
        Status status;// code statuses: 0 - created, 1 - confirmed, 2 - canceled, 3 - finished, 4 - returned/not paid by shop, 5 - returned/ paid by shop
        uint deliveryDate;
    }
        struct Products {
        uint id;
        string title;
        string describe;
        uint expirationPeriod;
    }
    struct Supplier {
        uint id;
        address wallet;
        string name;
    }
    struct SupplierStock {
        uint prodId;
        uint price;
        uint count;
    }
    struct Shop {
        string name;
        address wallet;
        uint debt;
    }
    struct ShopStock {
        uint prodId;
        uint shopId;
        uint price;
        uint count;
    }


    Shop[] shops;
    ShopStock[] dnsStock;
    Products[] dnsProducts;
    Supplier[] dnsSuppliers;
    SupplierStock[] supStock;
    Querries[] querries;
    Purshares[] purshares;
    Client[] private clientsChars;
    uint[] usedCodes; //from invited clients

    address owner;
    address requesterAdd;
    string _track;
    uint qurriesCount;
    uint clientsAddsCount;
    uint debtSize;
    uint invsCount;
    uint invitedCount;
    Role roleFrom;

//    mapping (address => Client) clientMapping; // адрес клиента => структура клиента !!ВРЕМЕННО НЕ ИСПОЛЬЗУЕТСЯ!!
    mapping(address => uint) clientsAddresses; // адрес клиента => id клиента (его индекс в массиве клиентов(clientChars))
    mapping(address => uint) shopsAddresses; // адрес магазина => id магазина 
    mapping(uint => address) invitedGuests; // Id приглашенного клиента => адрес приглашенного клиента
    mapping(address => uint) referalCodes; // адрес приглашенного (тот, кому адресован код) => реферальный код
    mapping(address => address[]) shopsDebts; // адрес магазина => массив клиентов, которым магазин задолжал
    mapping(uint => uint) Fines; // Id клиента (его индекс в массиве клиентов(clientChars)) => долг клиента


    constructor() {

        owner = msg.sender;

        dnsSuppliers.push(Supplier(1, 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4, "citilink"));
        dnsSuppliers.push(Supplier(2, 0x583031D1113aD414F02576BD6afaBfb302140225, "M.video"));
        supStock.push(SupplierStock(1, 1 * 10**18, 100));
        dnsStock.push(ShopStock(supStock[0].prodId, 1, supStock[0].price * 2, 20));
        dnsProducts.push(Products(1, "Shrimp", "Descr.", 5));
        shops.push(Shop("DNS", 0xdD870fA1b7C4700F2BD7f44238821C26f7392148, 0));
        shopsAddresses[shops[0].wallet] = 0;
    }

//Запускает только клиент. Генерирует код для указанного друга (по адресу). Принимает адресс друга, в качестве параметра
    function inviteYourFriend(address friendAddress) public OnlyClient() {
        require(friendAddress != msg.sender, "Error! You can`t invite yourself!");
        bool checkTheGuest = isInvitedFound(friendAddress);
        require(checkTheGuest != true, "Error! This user has already invited!");
        referalCodes[friendAddress] = generateRandNum(1000000);
        AddReferal(/*msg.sender,*/ friendAddress);
        console.log(referalCodes[friendAddress]);
    }

//Запускает только магазин. Подтверждает заказ со стороны магазина. Принимает bool значение, подтверждающее или отменяющее заказ и Id заказа, в качестве параметров
    function confirmOrder(bool isApproved, uint purshareId) public payable OnlyShops() {
        require(purshares[purshareId].status == Status.Created, "You confirmed/canceled this order early");
        if(isApproved == true) {
            uint delDate = makeDeliveryDate();
            purshares[purshareId].deliveryDate = delDate;
            purshares[purshareId].status = Status.Confirmed;
        } else if(isApproved == false) {
            require(msg.value >= dnsStock[purshares[purshareId].prodId].price * purshares[purshareId].count, "You don`t have enough Eth.");
            purshares[purshareId].status = Status.Canceled;
            payable(clientsChars[purshares[purshareId].clientId].wallet).transfer(dnsStock[purshares[purshareId].prodId].price * purshares[purshareId].count);
        }
    }

/*Запускает только клиент. Отправляет запрос на покупку магазину, со стороны клиента. Принимает Id "приобретаемого" продукта, его количества, Id магазина, в котором данный продукт приобретается и
Имя клиента, в качестве параметров*/
    function buyProd(uint _prodId, uint prodCount, uint shopId, string memory clientName) public OnlyClient() {
        require((dnsStock[_prodId].count - prodCount) >= 0, "Sorry! We don`t have enough count of this product!");
        dnsStock[_prodId].count -= prodCount;
        uint clientCheckId = clientsAddresses[msg.sender];
        if(clientCheckId == 0) {
            clientsChars.push(Client(msg.sender, clientName, false));
            clientsAddsCount ++;
            clientsAddresses[msg.sender] = clientsAddsCount;
        }
        _track = generateTrackNum(_prodId);
        purshares.push(Purshares(_track, clientsChars.length-1, _prodId, shopId, prodCount, generateRandNum(10), Status.Created, 0));
        purshares[purshares.length-1].trackNumber = _track;
        Fines[purshares.length-1] = dnsStock[purshares[purshares.length-1].prodId].price * purshares[purshares.length-1].count;
        console.log("Days from supply of this product is: ");
        console.log(purshares[purshares.length-1].daysFromSupply);
        console.log("Order number:");
        console.log(purshares.length-1);
        console.log("Your track code:");
        console.log(_track);
        console.log("You need to wait your order for: (temporarly in seconds)");
        console.log(5);
        console.log("Fine, if you reject this order (in 0,(Eth count)):");
        console.log((Fines[purshares.length-1] / 5) / 10 ** 17);
    }

/*Запускает только клиент. Сначала проверяет, является ли заказ клиента именно его заказом, и есть ли в нем просчроченные продукты (дни с момента поставки (генерируется рандомно)).
Принимает Id заказа, в качестве параметра*/
    function returnProducts(uint purshareId) public OnlyClient() OnlyExistingOrders(purshareId) {
        uint id;
        for(uint i = 0; i < clientsChars.length; i++) {
            if(clientsChars[i].wallet == msg.sender) {
                id = i;
                break;
            }
        }
        for(uint j = 0; j < purshares.length; j++) {
            if(j == purshareId) {
                require(id == purshares[j].clientId, "You wrote a wrong order number!");
                require(purshares[j].daysFromSupply > dnsProducts[purshares[j].prodId].expirationPeriod, "This order don`t have any experied products!");
                require(purshares[j].status == Status.Finished, "You can`t return order twice!");
                    uint _prodId = purshares[purshareId].prodId;
                    uint _prodCount = purshares[purshareId].count;
                    uint _prodPrice = dnsStock[purshares[purshareId].prodId].price;
                    debtSize = _prodCount * _prodPrice;
                    purshares[j].status = Status.ReturnedNotPaid;
                    dnsStock[_prodId].count += purshares[j].count;
                    shops[(dnsStock[_prodId].shopId)-1].debt += dnsStock[_prodId].price * dnsStock[_prodId].count;
                    shopsDebts[shops[(dnsStock[_prodId].shopId)-1].wallet].push(msg.sender);
                    break;
            }
        }
    }

//Запускает только магазин. Выводит (на данный момент в консоль) размер задолженности по введенному заказу. Принимает Id заказа, в качестве параметра
    function returnDebt(uint purshareId) public payable OnlyShops() {
        require(shopsDebts[msg.sender].length > 0, "You don`t have any debts!");
        require(purshareId < purshares.length, "This purshare is don`t created yet!");
        console.log("Your debt sum eth:");
        console.log(debtSize / 10**18);
    }

//Запускает только магазин. Выплачивает задолженность за конкретный заказ (если заказ находится в массиве возвращенных).
    function payDebt(uint purshareId, uint shopId) public payable OnlyShops() OnlyExistingOrders(purshareId) {
        require((dnsStock[(purshares[purshareId].prodId)-1].price * purshares[purshareId].count) <= msg.value, "You don`t have enough money to pay to this debt!");
        address[] memory debtTo = shopsDebts[msg.sender];
        uint clientOrder = purshares[purshareId].clientId;
        require(purshares[purshareId].status == Status.ReturnedPaid, "You have already paid this debt!");
        payable(debtTo[clientOrder]).transfer(debtSize);
        purshares[purshareId].status = Status.ReturnedPaid;
        delete debtTo[clientOrder];
        shops[shopId].debt -= debtSize;
        debtSize = 0;
    }

/*Запускает только магазин. Сначала проверяет, есть ли у поставщика нужное кол-во нужного товара и если есть, насильно списывает со склада поставщика на склад магазина
и переводит ему сумму за товары*/ 
    function supply(uint __prodId, uint _prodCount, uint supId) public payable OnlyShops() {
        require((supStock[supId].count - _prodCount) >= 0, "Sorry, we don`t have enough products");
        require((supStock[__prodId].price * _prodCount) <= msg.value, "You don`t have enough Eth");
        payable(dnsSuppliers[supId].wallet).transfer(supStock[__prodId].price * _prodCount);
        uint shopId = shopsAddresses[msg.sender];
        supStock[supId].count -= _prodCount;
        dnsStock[shopId].count += _prodCount;
    }

//Запускает любой пользователь. Отправляет запрос на изменение роли в системе со сменой (или установкой) имени. Принимает роль(из enum Role, фактически - Id роли) и Новое имя 
    function makeChangeRoleQuerry(Role _role, string memory name) public {
        querries.push(Querries(qurriesCount, msg.sender, name, _role));
        console.log("Querry id:");
        console.log(qurriesCount);
        qurriesCount++;
    }

/*Запускает только владелец. Подтверждает/Отменяет запрос на изменение роли в системе. При подтверждении - запускает метод changeRole (см. 336 строку),
а при отмене - выводит (пока в консоль) соответствующее сообщение (и не меняет роль, соответственно). Принимает Id подтверждаемого запроса и код подтверждения 
(да, я не догадался до bool)*/  
    function confirmRejectQuerry(int querryId, uint confirmCode) public OnlyOwner {
        require(querryId == 0 || querryId == 1, "You wrote a wrong confirm/reject code! 0 - reject, 1 - confirm!");
        if(confirmCode == 0) {
            console.log("Done! You have rejected this querry!");
        } else {
            changeRole(uint(querryId), querries[uint(querryId)].name);
            removeRole();
        }
    }

/*Запускает только клиент. Подтверждает получение покупки клиентом и оплачивает: 1. При получении - сумму покупки 2. При отмене - штраф (создается в buyProd(см.189 строку.)).
Также можно ввести реферальный код и заплатить на 10% меньше стоимости заказа, после чего код "сгорает". Принимает Id заказа, подтверждение клиента и код друга (0, если нет)*/
    function confirmPurshare(uint purshareId, bool isConfirmed, uint inviteCode) public payable OnlyClient {
        require(clientsChars[purshares[purshareId].clientId].wallet == msg.sender, "You enter a wrong number of order!");
        require(purshares[purshareId].status == Status.Confirmed, "This purshare must got confirm from shop or Finished yet!");
        require(block.timestamp >= purshares[purshareId].deliveryDate, "Your order isn`t delivered yet!");
        if(isConfirmed == true) {
            uint fullPrice = dnsStock[purshares[purshareId].prodId].price * purshares[purshareId].count;
            if(inviteCode != 0) {
                bool checkCode = isCodeUsed(inviteCode);
                require(checkCode == false, "This code has been used!");
                require(referalCodes[msg.sender] != 0, "This code isn`t for you!");
                fullPrice = makeDiscount(fullPrice);
                usedCodes.push(inviteCode);
            }
            require(fullPrice <= msg.value, "You don`t have enough Eth");
            payable(shops[purshares[purshareId].shopId].wallet).transfer(fullPrice);
            purshares[purshareId].status = Status.Finished;
        } else if(isConfirmed == false) {
            require(Fines[purshareId] <= msg.value, "You don`t have enough Eth.");
            payable(shops[purshares[purshareId].shopId].wallet).transfer(Fines[purshareId] / 5);
            Fines[purshareId] = 0;
            purshares[purshareId].status = Status.Canceled;
            dnsStock[purshares[purshareId].prodId].count += purshares[purshareId].count;
        }
    }

/*Запускает только владелец. Выводит все запросы на изменение роли (пока в консоль): Id запроса, адрес запросившего, новое имя, код роли*/
        function CheckQuerries() public view OnlyOwner(){
        for(uint i = 0; i < querries.length; i++){
            console.log("___________________________________________");
            console.log(querries[i].querryId);
            console.log(querries[i].requesterAddress);
            console.log(querries[i].name);
            console.log(uint(querries[i].role));
        }
    }

    //help private funcs

/*Добавляет реферала в mapping приглашенных клиентов, после проверки на существование клиента в этих массивах (см.366 строку).
Принимает адрес пригласившего и адрес приглашенного*/
    function AddReferal(address guest) private { 
        bool InvitedFound = isInvitedFound(guest);
        if(InvitedFound == false) {
            invitedGuests[invitedCount] = guest;
            invitedCount++;
        } else {
        }
        invsCount++;
    }

/*Изменяет роль пользователя: удаляет его из того массива той роли, в котором он хранился, а после переводил в массив запрашиваемой роли.
Принимает Id запроса и "новое" имя пользователя*/
    function changeRole(uint _querryId, string memory orgName) private {
        requesterAdd = querries[_querryId].requesterAddress;
        Role roleTo = querries[_querryId].role;
        roleFrom = defineUserRole(querries[_querryId].requesterAddress);
        require(roleTo != roleFrom, "You can`t change from your role on your role!");
        if(roleTo == Role.Shop) {
            shops.push(Shop(orgName, requesterAdd, 0));
        } else if(roleTo == Role.Supplier) {
            dnsSuppliers.push(Supplier(dnsSuppliers.length-1, requesterAdd, orgName));
        } else  if(roleTo == Role.Client) {
            clientsChars.push(Client(requesterAdd, orgName, false));
        }
        removeRole();
    }

//Часть метода changeRole (см. 339 строку). Проверяет, к какой роли относится пользователь, а затем удаляет его из массива соответствующей роли
    function removeRole() private {
        if(roleFrom == Role.Shop){
            delete shops[findByAdd(1, requesterAdd)];
        } else if(roleFrom == Role.Supplier) {
            delete dnsSuppliers[findByAdd(2, requesterAdd)];
        } else if(roleFrom == Role.Client) {
            delete clientsChars[findByAdd(0, requesterAdd)];
        }
    }

//Генерирует трек номер по принципу: "AA" + название продукта + описание продукта (по ТЗ Ивана). Принимает Id продукта
    function generateTrackNum(uint prodId) private view returns(string memory) {
        string memory _title = dnsProducts[prodId].title;
        string memory _descr = dnsProducts[prodId].describe;
        return string.concat("AA", _title, _descr);
    }

/* Генерирует рандомный номер, принимающий в качестве параметра значность числа (измеряется в модуле, остаток от деления на который будет определять значимость):
10 - 2-х значное, 100 - 3-х значное и т.д.*/
    function generateRandNum(uint module) private view returns(uint) {
        return uint(keccak256(abi.encodePacked(block.timestamp, msg.sender))) % module;
    }

//Проверяет, был ли гость(пользователь реф.ссылки) приглашен ранее. Принимает адрес гостя
    function isInvitedFound(address _guest) private view returns(bool) {
        for(uint i = 0; i < invitedCount; i++){
            if(invitedGuests[i] == _guest) {
                return true;
            }
        }
        return false;
    } 

//Проверяет, был ли рефераьлный код использован ранее. Принимает проверяемый код
    function isCodeUsed(uint codeToCheck) private view returns(bool) {
        for(uint i = 0; i < usedCodes.length; i++) {
            if(codeToCheck == usedCodes[i]) {
                return true;
            }
        }
        return false;
    }

//Определяет(и возвращает) Id пользователя в массиве его роли, по его адресу. Принимает код роли и адрес пользователя. Если не находит, возвращает 0 
    function findByAdd(uint roleCode, address userAdd) private view returns(uint) {
       if(roleCode == 1) {
           for(uint i = 0; i < shops.length; i++) {
               if(userAdd == shops[i].wallet) {
                   return i;
               }
           }
        }
        if(roleCode == 2) {
           for(uint i = 0; i < dnsSuppliers.length; i++) {
               if(userAdd == dnsSuppliers[i].wallet) {
                   return i;
               }
           }
        }
        if(roleCode == 0) {
           for(uint i = 0; i < clientsChars.length; i++) {
               if(userAdd == clientsChars[i].wallet) {
                   return i;
               }
           }
        }
        return 0;
    }

//Определяет(и возвращает) код роли пользователя по его адресу. Принимает адрес пользователя
    function defineUserRole(address userAddress) private view returns(Role) {
        for(uint i = 0; i < clientsChars.length; i++) {
            if(clientsChars[i].wallet == userAddress) {
                return Role.Client;
            }
        }
        for(uint i = 0; i < shops.length; i++) {
            if(shops[i].wallet == userAddress) {
                return Role.Shop;
            }
        }
        for(uint i = 0; i < dnsSuppliers.length; i++) {
            if(dnsSuppliers[i].wallet == userAddress) {
                return Role.Supplier;
            }
        }
        return Role.Client;
    }

//Создает и возвращает дату доставки товара. Определяется рандомно
    function makeDeliveryDate() private view returns(uint) { // make a delivery date 
        uint thisMoment = block.timestamp;
        return thisMoment + 2 seconds;
    }

//Если пользователь вводит валидный реферальный код (см. 291 строку) возвращают новую стоимость товара - со скидкой 10%
    function makeDiscount(uint price) private pure returns(uint) {
        uint newPrice = price - (price / 10);
        return newPrice;
    }
}