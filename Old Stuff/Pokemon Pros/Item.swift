//
//  Item.swift
//  Pokemon Pros
//
//  Created by Mihir Panchal on 2026-08-31.
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
