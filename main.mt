val variable = 1 + (2 + 3) * 4 * (3 - 4);
val otherVariable = (1 + variable) * 4;
val hiAnnaLena = variable * variable + otherVariable;
{
    val innerScopeVar = hiAnnaLena + 1;
    val anotherVar = innerScopeVar * 2;
}
val firstBoolean = true;
val myFirstTypedBoolean: boolean = true;
val myFirstTypedInteger: int = 2;
val someNegativeInt = -1;
val someExpression = 1 + 2;
val blockResult = {
    val a = hiAnnaLena;
    val b = hiAnnaLena * 2;
    a + b + 1
};
