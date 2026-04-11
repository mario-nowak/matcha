item myFunction(parameter: int): int = parameter * 2;

item myFunctionWithComplexBody(parameter: int): boolean = {
    if parameter >= 0 {
        return true;
    } else {
        return false;
    };
};


item myFunctionToTestControlFlowValidation(parameter: int): unit = {
    if parameter == 0 {
        return;
    }
};


myFunctionToTestControlFlowValidation(3);

item g(): int = 3 + 2;
item f(g: int): int = g;

printInt(f(3));
printInt(g());
