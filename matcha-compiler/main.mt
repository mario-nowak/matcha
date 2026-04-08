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

var this_is_mutable = 10;
printInt(this_is_mutable);
this_is_mutable = this_is_mutable * 2;
printInt(this_is_mutable);

var n = 6;
var sum = 0;
var i = 0;
loop {
    if i >= n {
        leave;
    }

    var j = 1;
    loop {

        sum = sum + j;

        j = j + 1;
        if j > i+1 {
            leave;
        }
    }

    i = i + 1;
}

printInt(sum);

printInt(0);
var limit = 5;
var is_even = false;
var uneven_sum = 0;
var counter = 1;
loop {
    if counter >= limit {
        leave;
    }

    if is_even {
        counter = counter + 1;
        is_even = not is_even;
        continue;
    } else {
        uneven_sum = uneven_sum + counter;
        printInt(uneven_sum);
    };

    counter = counter + 1;
    is_even = not is_even;
}

printInt(0);
printInt(uneven_sum);

var x_00001 = 1;
if x_00001 <= 10 {
    x_00001 = x_00001 + 1;
}
printInt(x_00001);

var is_true = true;
while is_true {
    is_true = false;
}


var x_02 = 0;
while x_02 < 10 {
    printInt(x_02);
    x_02 = x_02 + 1;
}