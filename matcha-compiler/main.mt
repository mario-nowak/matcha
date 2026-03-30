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
};

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
    a + b + if not unknown { 1 } else { 2 }
};

val i_had_a_coffee = true;
val i_had_an_ice_cream = false;

val im_happy = i_had_a_coffee or i_had_an_ice_cream;
val im_really_happy = i_had_a_coffee and i_had_an_ice_cream;

val happiness_score = if im_happy {
    if im_really_happy { 2 } else { 1 }
} else {
    0
};

val im_happy_confirmed = happiness_score >= 1;
val exit_code = if im_happy_confirmed { 1 } else { 0 };