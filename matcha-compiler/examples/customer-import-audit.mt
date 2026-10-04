// A decision is exactly one of three cases. Only the problem cases carry a reason.
item AuditDecision = union {
    Valid,
    Invalid: string,
    Suspicious: string,

    item needsAttention(self: AuditDecision): boolean = match self {
        .Valid => false,
        else => true,
    };

    item describe(self: AuditDecision): string = match self {
        .Valid => "[valid]: ok",
        .Invalid(reason) => "[invalid]: " + reason,
        .Suspicious(reason) => "[suspicious]: " + reason,
    };
};

item CustomerSubscription = structure {
    customerId: string;
    importedPlan: string;
    plan: string;
    seats: int;
    active: boolean;

    // Keep imported and normalized plan labels so the audit can show source-data cleanup.
    item fromRow(row: string): CustomerSubscription = {
        val fields = row.split("|");
        val importedPlan = fields[1].trim();

        return .{
            customerId = fields[0].trim(),
            importedPlan = importedPlan,
            plan = match importedPlan {
                "basic" => "basic",
                "starter" => "basic",
                "team" => "team",
                "pro" => "team",
                "enterprise" => "enterprise",
                "corp" => "enterprise",
                else => "unknown",
            },
            seats = fields[2].trim().toInt(),
            active = fields[3].trim().toInt() == 1,
        };
    };

    item classify(self: CustomerSubscription): AuditDecision = match {
        self.plan == "unknown" => .Invalid("unknown imported plan: " + self.importedPlan),
        self.seats <= 0 => .Invalid("non-positive seat count"),
        self.active == false and self.seats > 0 => .Suspicious("inactive account still has seats assigned"),
        self.plan == "enterprise" and self.seats < 100 => .Suspicious("enterprise account with very low seats"),
        self.plan == "basic" and self.seats > 50 => .Suspicious("basic plan with unusually high seats"),
        else => .Valid,
    };

    item normalizationDetails(self: CustomerSubscription): string = match {
        self.importedPlan != self.plan => " (plan " + self.importedPlan + " -> " + self.plan + ")",
        else => "",
    };

    item findingLine(self: CustomerSubscription, decision: AuditDecision): string = self.customerId
        + " "
        + decision.describe()
        + self.normalizationDetails();
};

item AuditSummary = structure {
    valid: int;
    invalid: int;
    suspicious: int;

    item empty(): AuditSummary = .{
        valid = 0,
        invalid = 0,
        suspicious = 0,
    };

    // The match is exhaustive, so a new decision case cannot be silently miscounted.
    item record(self: AuditSummary, decision: AuditDecision): unit = match decision {
        .Valid => {
            self.valid = self.valid + 1;
        },
        .Invalid => {
            self.invalid = self.invalid + 1;
        },
        .Suspicious => {
            self.suspicious = self.suspicious + 1;
        },
    };

    item print(self: AuditSummary): unit = {
        printString("Total: " + (self.valid + self.invalid + self.suspicious).toString());
        printString("Valid: " + self.valid.toString());
        printString("Invalid: " + self.invalid.toString());
        printString("Suspicious: " + self.suspicious.toString());
    };
};

item auditFile(path: string): AuditSummary = {
    val rows = readFile(path).trim().split("\n");
    var summary = AuditSummary.empty();

    for row in rows {
        val subscription = CustomerSubscription.fromRow(row);
        val decision = subscription.classify();

        summary.record(decision);

        if decision.needsAttention() {
            printString(subscription.findingLine(decision));
        }
    }

    return summary;
};

val arguments = getArguments();
val summary = auditFile(arguments[0]);
summary.print();
