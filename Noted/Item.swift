//
//  Item.swift
//  Noted
//
//  Created by Nadia Woo on 5/3/26.
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
