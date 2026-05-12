item AuditDecision = structure {
    status: string;
    reason: string;

    item valid(): AuditDecision = .{
        status = "valid",
        reason = "ok",
    };

    item invalid(reason: string): AuditDecision = .{
        status = "invalid",
        reason = reason,
    };

    item suspicious(reason: string): AuditDecision = .{
        status = "suspicious",
        reason = reason,
    };

    item needsAttention(self: AuditDecision): boolean = self.status != "valid";
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
        self.plan == "unknown" => AuditDecision.invalid("unknown imported plan: " + self.importedPlan),
        self.seats <= 0 => AuditDecision.invalid("non-positive seat count"),
        self.active == false and self.seats > 0 => AuditDecision.suspicious("inactive account still has seats assigned"),
        self.plan == "enterprise" and self.seats < 100 => AuditDecision.suspicious("enterprise account with very low seats"),
        self.plan == "basic" and self.seats > 50 => AuditDecision.suspicious("basic plan with unusually high seats"),
        else => AuditDecision.valid(),
    };

    item normalizationDetails(self: CustomerSubscription): string = match {
        self.importedPlan != self.plan => " (plan " + self.importedPlan + " -> " + self.plan + ")",
        else => "",
    };

    item findingLine(self: CustomerSubscription, decision: AuditDecision): string = self.customerId
        + " ["
        + decision.status
        + "]: "
        + decision.reason
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

    item record(self: AuditSummary, decision: AuditDecision): unit = match decision.status {
        "valid" => {
            self.valid = self.valid + 1;
        },
        "invalid" => {
            self.invalid = self.invalid + 1;
        },
        else => {
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
