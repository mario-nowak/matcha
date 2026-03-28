val variable = 1 + (2 + 3) * 4 * (3 - 4);
val otherVariable = (1 + variable) * 4;
val hiAnnaLena = variable * variable + otherVariable;
{
    val innerScopeVar = hiAnnaLena + 1;
    val anotherVar = innerScopeVar * 2;
}

val someBool: boolean = false;
if someBool {
    val scoped = 4;
}

if someBool {
    val onlyWhenTrue = 3;
} else {
    val onlyWhenTrue = 5;
}

val ifExpression = if someBool { 3 } else { 4 };

val outer = if true {
    if false {
        1
    } else {
        2
    }
} else {
    3
};
val x = (if true { if false { 1 } else { 2 } } else { 3 }) + 4;


val firstBoolean = true;
val myFirstTypedBoolean: boolean = true;
val myFirstTypedInteger: int = 2;
val someNegativeInt = -1;
val someExpression = 1 + 2;
val blockResult = {
    val a = hiAnnaLena;
    val b = hiAnnaLena * 2;
    val unknown = false;
    a + b + if unknown { 1 } else { 2 }
};
