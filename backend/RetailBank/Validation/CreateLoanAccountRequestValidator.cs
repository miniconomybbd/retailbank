﻿using FluentValidation;
using RetailBank.Models.Dtos;

namespace RetailBank.Validation;

public class CreateLoanAccountRequestValidator : AbstractValidator<CreateLoanAccountRequest>
{
    public CreateLoanAccountRequestValidator()
    {
        RuleFor(req => req.LoanAmountCents)
            .NotEmpty()
            .WithMessage("Cannot take out a loan of 0 cents.");
        RuleFor(req => req.DebtorAccountId)
            .Length(12)
            .Matches(ValidationConstants.Base10)
            .WithMessage("Debtor account number is not a valid transactional account number.");
    }
}
