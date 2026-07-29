//
//  Item.swift
//  Tallassee Sawmill AG & Rentals Contracts
//
//  Created by Tim on 6/27/26.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
