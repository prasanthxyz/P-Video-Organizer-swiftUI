import Combine
import Foundation

struct RpsData: Codable {
    var rpsConfig: RpsConfig

    var videoNames: [String]
    var galleryNames: [String]
    var tagNames: [String]

    var videoGalleries: [String: [String]]
    var videoTags: [String: [String]]
    var galleryImages: [String: [String]]

    var selectedVideos: Set<String>
    var selectedGalleries: Set<String>
    var selectedTags: Set<String>

    var combinations: [Combination]
    var combinationIndex: Int

    var isTgpShown: Bool
    var isVideoPlaying: Bool

    init(rpsConfig: RpsConfig) {
        self.rpsConfig = rpsConfig
        self.videoNames = []
        self.galleryNames = []
        self.tagNames = []

        self.videoGalleries = [String: [String]]()
        self.videoTags = [String: [String]]()
        self.galleryImages = [String: [String]]()

        self.selectedVideos = Set<String>()
        self.selectedGalleries = Set<String>()
        self.selectedTags = Set<String>()

        self.combinations = []
        self.combinationIndex = 0

        self.isTgpShown = true
        self.isVideoPlaying = false
    }

    mutating func moveToNextCombination() {
        if (self.combinations.isEmpty) {
            return
        }
        self.combinationIndex = (self.combinationIndex + 1) % self.combinations.count
    }

    mutating func moveToPrevCombination() {
        if (self.combinations.isEmpty) {
            return
        }
        self.combinationIndex = (self.combinationIndex - 1 + self.combinations.count) % self.combinations.count
    }

    func getCurrentCombination() -> Combination {
        if (self.combinations.isEmpty) {
            print("No combinations found.")
            exit(2)
        }
        return self.combinations[self.combinationIndex]
    }
}

struct Combination: Codable, Equatable {
    var videoName: String
    var galleryName: String

    init(videoName: String, galleryName: String) {
        self.videoName = videoName
        self.galleryName = galleryName
    }
}

struct RpsConfig: Codable {
    var vidPath: String
    var namPath: String
    var tags: [String]
    var videoRelations: [String: VideoRelations]
}

struct VideoRelations: Codable {
    var galleries: [String]
    var tags: [String]
}

func load<T: Decodable>(_ filename: URL, as type: T.Type = T.self) -> T {
    let data: Data

    do {
        data = try Data(contentsOf: filename)
    } catch {
        fatalError("Couldn't load \(filename) from main bundle:\n\(error)")
    }

    do {
        let decoder = JSONDecoder()
        return try decoder.decode(T.self, from: data)
    } catch {
        fatalError("Couldn't parse \(filename) as \(T.self):\n\(error)")
    }
}

class RpsDataViewModel: ObservableObject {
    @Published var data: RpsData

    init() {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("pvorg.json")
        let rpsConfig: RpsConfig = load(fileURL)
        self.data = RpsData(rpsConfig: rpsConfig)
        self.reloadData(rpsConfigIn: rpsConfig)
    }

    func reloadData(rpsConfigIn: RpsConfig? = nil) {
        let fileURL = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("pvorg.json")
        let rpsConfig = rpsConfigIn != nil ? rpsConfigIn! : load(fileURL)
        self.data.rpsConfig = rpsConfig
        self.data.videoNames = getVideoNames(rpsConfig: rpsConfig)
        self.data.galleryNames = getGalleryNames(rpsConfig: rpsConfig)
        self.data.tagNames = rpsConfig.tags
        self.data.videoGalleries = getVideoGalleries(rpsConfig: rpsConfig, videoNames: self.data.videoNames, galleryNames: self.data.galleryNames)
        self.data.videoTags = getVideoTags(rpsConfig: rpsConfig, videoNames: self.data.videoNames, tagNames: self.data.tagNames)
        self.data.galleryImages = getGalleryImages(rpsConfig: rpsConfig, galleryNames: self.data.galleryNames)
        self.data.selectedVideos = Set(self.data.videoNames)
        self.data.selectedGalleries = Set(self.data.galleryNames)
        self.data.selectedTags = Set()
        self.generateCombinations()
    }

    func generateCombinations() {
        var combinations: [Combination] = []
        for video in self.data.selectedVideos {
            guard let videoGalleries = self.data.videoGalleries[video],
                  let videoTags = self.data.videoTags[video] else {
                continue
            }

            if !self.data.selectedTags.isEmpty && !self.data.selectedTags.isSubset(of: Set(videoTags)) {
                continue
            }

            for gallery in videoGalleries {
                if self.data.selectedGalleries.contains(gallery) {
                    combinations.append(Combination(videoName: video, galleryName: gallery))
                }
            }
        }
        self.data.combinations = combinations.shuffled()
        self.data.combinationIndex = 0
    }
}

func getVideoNames(rpsConfig: RpsConfig) -> [String] {
    var videoNames: [String] = []
    let fileManager = FileManager.default
    let videoPath = URL(fileURLWithPath: rpsConfig.vidPath)

    do {
        let fileURLs = try fileManager.contentsOfDirectory(at: videoPath, includingPropertiesForKeys: nil)

        for fileURL in fileURLs {
            if fileURL.hasDirectoryPath == false && fileURL.lastPathComponent.first != "." {
                videoNames.append(fileURL.lastPathComponent)
            }
        }
    } catch {
        return []
    }
    return videoNames
}

func getGalleryNames(rpsConfig: RpsConfig) -> [String] {
    var galleryNames: [String] = []
    let fileManager = FileManager.default
    let galleryPath = URL(fileURLWithPath: rpsConfig.namPath)

    do {
        let fileURLs = try fileManager.contentsOfDirectory(at: galleryPath, includingPropertiesForKeys: nil)

        for fileURL in fileURLs {
            if fileURL.hasDirectoryPath && fileURL.lastPathComponent.first != "." {
                galleryNames.append(fileURL.lastPathComponent)
            }
        }
    } catch {
        return []
    }
    return galleryNames
}

func getVideoGalleries(rpsConfig: RpsConfig, videoNames: [String], galleryNames: [String]) -> [String: [String]] {
    var videoGalleries: [String: [String]] = [:]
    for videoName in videoNames {
        if rpsConfig.videoRelations[videoName] == nil {
            videoGalleries[videoName] = galleryNames
        } else {
            videoGalleries[videoName] = []
            if let galleries = rpsConfig.videoRelations[videoName]?.galleries {
                for galleryName in galleries {
                    if galleryNames.contains(galleryName) {
                        videoGalleries[videoName]?.append(galleryName)
                    }
                }
            }
        }
    }
    return videoGalleries
}

func getVideoTags(rpsConfig: RpsConfig, videoNames: [String], tagNames: [String]) -> [String: [String]] {
    var videoTags: [String: [String]] = [:]
    for videoName in videoNames {
        videoTags[videoName] = []
        if let videoRelation = rpsConfig.videoRelations[videoName] {
            for tagName in videoRelation.tags {
                if tagNames.contains(tagName) {
                    videoTags[videoName]?.append(tagName)
                }
            }
        }
    }
    return videoTags
}

func getGalleryImages(rpsConfig: RpsConfig, galleryNames: [String]) -> [String: [String]] {
    let imageExts: Set<String> = ["png", "jpg", "jpeg", "bmp", "gif"]
    var galleryImages: [String: [String]] = [:]
    for galleryName in galleryNames {
        var imgList = [String]()
        let galleryPath = URL(fileURLWithPath: rpsConfig.namPath).appendingPathComponent(galleryName)
        do {
            let files = try FileManager.default.contentsOfDirectory(at: galleryPath, includingPropertiesForKeys: nil)
            for imgPath in files {
                if imgPath.isFileURL && imageExts.contains(imgPath.pathExtension.lowercased()) && imgPath.lastPathComponent.first != "." {
                    imgList.append(imgPath.path)
                }
            }
        } catch {
        }
        if !imgList.isEmpty {
            galleryImages[galleryName] = imgList
        }
    }

    return galleryImages
}
