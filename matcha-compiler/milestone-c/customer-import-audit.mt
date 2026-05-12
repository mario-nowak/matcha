item AuditDecision = structure {
    statusCode: int; // 0 valid, 1 invalid, 2 suspicious
    reason: string;

    item valid(): AuditDecision = .{
        statusCode = 0,
        reason = "ok",
    };

    item invalid(reason: string): AuditDecision = .{
        statusCode = 1,
        reason = reason,
    };

    item suspicious(reason: string): AuditDecision = .{
        statusCode = 2,
        reason = reason,
    };
};

item CustomerSubscription = structure {
    customerId: string;
    planCode: int;
    seats: int;
    active: boolean;

    item fromRow(row: string): CustomerSubscription = {
        val fields = row.split("|");

        return .{
            customerId = fields[0].trim(),
            planCode = fields[1].trim().toInt(),
            seats = fields[2].trim().toInt(),
            active = fields[3].trim().toInt() == 1,
        };
    };

    item isEnterprise(self: CustomerSubscription): boolean = self.planCode == 3;

    item classify(self: CustomerSubscription): AuditDecision = match {
        self.planCode < 1 or self.planCode > 3 => AuditDecision.invalid("unknown plan code"),
        self.seats <= 0 => AuditDecision.invalid("non-positive seat count"),
        self.isEnterprise() and self.seats < 100 => AuditDecision.suspicious("enterprise account with very low seats"),
        self.planCode == 1 and self.seats > 50 => AuditDecision.suspicious("basic plan with unusually high seats"),
        else => AuditDecision.valid(),
    };
};

item AuditSummary = structure {
    total: int;
    valid: int;
    invalid: int;
    suspicious: int;

    item empty(): AuditSummary = .{
        total = 0,
        valid = 0,
        invalid = 0,
        suspicious = 0,
    };

    item applied(self: AuditSummary, decision: AuditDecision): AuditSummary = match decision.statusCode {
        0 => .{
            total = self.total + 1,
            valid = self.valid + 1,
            invalid = self.invalid,
            suspicious = self.suspicious,
        },
        1 => .{
            total = self.total + 1,
            valid = self.valid,
            invalid = self.invalid + 1,
            suspicious = self.suspicious,
        },
        else => .{
            total = self.total + 1,
            valid = self.valid,
            invalid = self.invalid,
            suspicious = self.suspicious + 1,
        },
    };

    item print(self: AuditSummary): unit = {
        printString("Total: " + self.total.toString());
        printString("Valid: " + self.valid.toString());
        printString("Invalid: " + self.invalid.toString());
        printString("Suspicious: " + self.suspicious.toString());
    };
};

val arguments = getArguments();
val rows = readFile(arguments[0]).trim().split("\n");
var summary = AuditSummary.empty();

for row in rows {
    val subscription = CustomerSubscription.fromRow(row);
    val decision = subscription.classify();

    summary = summary.applied(decision);

    if decision.reason != "ok" {
        val recommendation = match decision.reason {
            "unknown plan code" => "check plan mapping in source data",
            "non-positive seat count" => "verify seat count in billing system",
            "enterprise account with very low seats" => "confirm enterprise plan assignment",
            else => "review account for unusual seat distribution",
        };
        printString(subscription.customerId + ": " + decision.reason + " (" + recommendation + ")");
    }
}

summary.print();
