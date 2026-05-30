import { NextResponse } from "next/server";

export async function POST(request: Request) {
    const bill = await request.json()

    const results = {
        accountNumber: bill.accountNumber,
        checks: {
            estimatedRead: {
                passed: bill.readType != "estimated",
                message: bill.readType === "estimated" 
                ? "Warning: Estimated read detected - munnicipality may owe correction"
                : "Actual read confirmed" 
            }
        }
    }
    
    return NextResponse.json(results);
}